import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../rust/api/link.dart' as link;
import '../model.dart';
import 'grid.dart';

enum LinkStatus { disconnected, connecting, connected }

/// One session as the daemon reports it (orc_protocol::SessionSummary).
class LiveSession {
  const LiveSession(
    this.id,
    this.accountId,
    this.cwd,
    this.state,
    this.model, {
    this.projectId,
    this.branch,
  });

  final String id;
  final String accountId;
  final String cwd;

  /// starting, running, waiting_input, idle, exited.
  final String state;
  final String? model;

  factory LiveSession.fromJson(Map<String, dynamic> j) => LiveSession(
    j['id'] as String,
    j['account_id'] as String,
    j['cwd'] as String,
    j['state'] as String,
    j['model'] as String?,
    projectId: j['project_id'] as String?,
    branch: j['branch'] as String?,
  );

  /// Set when the session runs in a project worktree.
  final String? projectId;
  final String? branch;

  LiveSession withState(String s) => LiveSession(
    id,
    accountId,
    cwd,
    s,
    model,
    projectId: projectId,
    branch: branch,
  );
}

class LiveQuota {
  const LiveQuota(
    this.fiveHour,
    this.fiveHourResetsAt,
    this.sevenDay,
    this.sevenDayResetsAt,
    this.readAt,
  );

  final double? fiveHour;
  final DateTime? fiveHourResetsAt;
  final double? sevenDay;
  final DateTime? sevenDayResetsAt;
  final DateTime readAt;
}

/// A session's screen; terminals listen to it directly, so 30 fps of grid
/// updates never rebuild the rest of the app.
class LiveGrid extends ChangeNotifier {
  final state = GridState();

  void apply(Map<String, dynamic> diff) {
    state.apply(diff);
    notifyListeners();
  }
}

/// A workspace browser as the daemon streams it. Panes listen to it
/// directly, so frames never rebuild the rest of the app.
class LiveBrowser extends ChangeNotifier {
  bool open = false;
  String url = '';

  /// Last screen (JPEG) and the page size it shows, in CSS pixels.
  Uint8List? frame;
  int width = 0;
  int height = 0;
}

/// The app's connection to orcd: pairing, connecting (with retry), and the
/// live state it reports. Notifies on session, account and quota changes.
class DaemonClient extends ChangeNotifier {
  LinkStatus status = LinkStatus.disconnected;
  String? error;
  List<String> accounts = [];
  List<LiveSession> sessions = [];
  final quotas = <String, LiveQuota>{};
  final grids = <String, LiveGrid>{};

  /// The daemon's catalog (orc_protocol::CatalogEntry JSON) and templates.
  List<Map<String, dynamic>> catalog = [];
  List<Map<String, dynamic>> templates = [];

  /// Env values agents asked to store, waiting for you: (id, session, name).
  List<(String, String, String)> envRequests = [];

  /// Recent messages between sessions: (from, to, body), newest last.
  List<(String, String, String)> messages = [];

  void resolveEnvRequest(String id, bool approve) {
    send({'type': 'resolve_env_request', 'id': id, 'approve': approve});
    envRequests = envRequests.where((r) => r.$1 != id).toList();
    notifyListeners();
  }

  void dismissMessages() {
    messages = [];
    notifyListeners();
  }

  /// Local repositories the daemon makes worktrees from.
  List<Map<String, dynamic>> projects = [];

  /// Plans (orc_protocol::PlanDoc JSON) and, per started plan, its cards
  /// (orc_protocol::CardRun JSON).
  List<Map<String, dynamic>> plans = [];
  final planRuns = <String, List<Map<String, dynamic>>>{};

  void savePlan(Map<String, Object?> doc) =>
      send({'type': 'save_plan', 'plan': doc});

  void startPlan(
    String planId,
    String accountId,
    List<Map<String, Object?>> cards,
  ) => send({
    'type': 'start_plan',
    'plan_id': planId,
    'account_id': accountId,
    'cards': cards,
  });

  void retryCard(String planId, int number) =>
      send({'type': 'retry_card', 'plan_id': planId, 'number': number});

  void askPlanner(String planId, String accountId, String request) => send({
    'type': 'ask_planner',
    'plan_id': planId,
    'account_id': accountId,
    'request': request,
  });

  /// Workspace browsers by profile.
  final browsers = <String, LiveBrowser>{};

  LiveBrowser browserOf(String profile) =>
      browsers.putIfAbsent(profile, LiveBrowser.new);

  /// [action] is orc_protocol::BrowserAction JSON (`{'action': 'open', …}`).
  void browser(String profile, Map<String, Object?> action) =>
      send({'type': 'browser', 'profile': profile, 'action': action});

  /// Last diff per session: (base branch, files).
  final diffs = <String, (String, List<Map<String, dynamic>>)>{};

  /// Last PR status per session (gh pr view JSON), null when no PR.
  final prs = <String, Map<String, dynamic>?>{};

  /// Last search: (query, hits, truncated).
  (String, List<Map<String, dynamic>>, bool)? search;

  void addProject(String name, String repo, String base) => send({
    'type': 'add_project',
    'name': name,
    'repo': repo,
    'base_branch': base,
  });

  void createWorktreeSession(
    String projectId,
    String branch,
    String accountId,
  ) => send({
    'type': 'create_worktree_session',
    'project_id': projectId,
    'branch': branch,
    'account_id': accountId,
    'profile': <String, Object?>{},
    'cols': 100,
    'rows': 30,
  });

  void requestDiff(String sessionId) {
    send({'type': 'diff', 'session_id': sessionId});
    send({'type': 'pr_status', 'session_id': sessionId});
  }

  void runSearch(
    String query, {
    String? sessionId,
    String? projectId,
    bool regex = false,
  }) => send({
    'type': 'search',
    'session_id': sessionId,
    'project_id': projectId,
    'query': query,
    'regex': regex,
  });

  /// Running totals per session: (tokens, cost in USD).
  final usage = <String, (int, double)>{};

  /// The last usage report asked for (day, account, model rows).
  List<UsageRow> usageRows = [];

  void requestUsage(int days) => send({'type': 'usage_report', 'days': days});

  /// Last "Testar conexão" result per MCP id: (ok, tools, error).
  final mcpTests = <String, (bool, int, String?)>{};

  link.DaemonLink? _link;
  StreamSubscription<String>? _sub;
  Timer? _retry;
  bool _disposed = false;

  /// Paired, or already talking to a daemon.
  bool get paired => _identity != null || accounts.isNotEmpty;
  String? _identity;

  Future<File> _identityFile() async => File(
    '${(await getApplicationSupportDirectory()).path}/daemon-identity.json',
  );

  /// Loads a stored pairing and connects, if there is one.
  Future<void> start() async {
    try {
      final f = await _identityFile();
      if (await f.exists()) {
        _identity = await f.readAsString();
        await connect();
      }
    } catch (e) {
      _fail('$e');
    }
  }

  /// Pairs with the ticket from `orcd pair`, stores the identity, connects.
  Future<void> pair(String ticket) async {
    status = LinkStatus.connecting;
    error = null;
    notifyListeners();
    try {
      final identity = await link.pairDevice(
        ticket: ticket.trim(),
        deviceName: Platform.localHostname,
      );
      final f = await _identityFile();
      await f.create(recursive: true);
      await f.writeAsString(identity);
      _identity = identity;
      await connect();
    } catch (e) {
      _fail('$e');
    }
  }

  Future<void> connect() async {
    final identity = _identity;
    if (identity == null || _disposed) return;
    _retry?.cancel();
    status = LinkStatus.connecting;
    notifyListeners();
    try {
      final l = await link.connectDaemon(identity: identity);
      _link = l;
      _sub = l.listen().listen(handle);
      status = LinkStatus.connected;
      error = null;
      notifyListeners();
    } catch (e) {
      _fail('$e');
      _scheduleRetry();
    }
  }

  /// Applies one daemon message (JSON of orc_protocol::DaemonMessage).
  @visibleForTesting
  void handle(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    switch (m['type']) {
      case 'hello':
        accounts = (m['accounts'] as List).cast<String>();
        notifyListeners();
      case 'sessions':
        sessions = [
          for (final s in m['sessions'] as List)
            LiveSession.fromJson(s as Map<String, dynamic>),
        ];
        grids.removeWhere((id, _) => !sessions.any((s) => s.id == id));
        for (final s in sessions) {
          if (!grids.containsKey(s.id)) {
            grids[s.id] = LiveGrid();
            send({'type': 'snapshot', 'session_id': s.id});
          }
        }
        notifyListeners();
      case 'session_state':
        sessions = [
          for (final s in sessions)
            s.id == m['session_id'] ? s.withState(m['state'] as String) : s,
        ];
        notifyListeners();
      case 'grid':
        grids
            .putIfAbsent(m['session_id'] as String, LiveGrid.new)
            .apply(m['snapshot'] as Map<String, dynamic>);
      case 'grid_diff':
        grids
            .putIfAbsent(m['session_id'] as String, LiveGrid.new)
            .apply(m['diff'] as Map<String, dynamic>);
      case 'quota':
        final l = m['limits'] as Map<String, dynamic>;
        DateTime? at(Object? w) => w is Map
            ? DateTime.fromMillisecondsSinceEpoch(
                (w['resets_at'] as int) * 1000,
              )
            : null;
        double? pct(Object? w) =>
            w is Map ? (w['used_percentage'] as num).toDouble() : null;
        quotas[m['account_id'] as String] = LiveQuota(
          pct(l['five_hour']),
          at(l['five_hour']),
          pct(l['seven_day']),
          at(l['seven_day']),
          DateTime.fromMillisecondsSinceEpoch((m['read_at'] as int) * 1000),
        );
        notifyListeners();
      case 'catalog':
        catalog = (m['entries'] as List).cast<Map<String, dynamic>>();
        templates = (m['templates'] as List).cast<Map<String, dynamic>>();
        notifyListeners();
      case 'session_usage':
        final u = m['usage'] as Map<String, dynamic>;
        usage[m['session_id'] as String] = (
          (u['input'] as int) +
              (u['output'] as int) +
              (u['cache_read'] as int) +
              (u['cache_creation'] as int),
          (u['cost_usd'] as num).toDouble(),
        );
        notifyListeners();
      case 'usage_report':
        usageRows = [
          for (final r in (m['rows'] as List).cast<Map<String, dynamic>>())
            () {
              final u = r['usage'] as Map<String, dynamic>;
              return UsageRow(
                r['day'] as String,
                r['account_id'] as String,
                r['model'] as String,
                (u['input'] as int) +
                    (u['output'] as int) +
                    (u['cache_read'] as int) +
                    (u['cache_creation'] as int),
                (u['cost_usd'] as num).toDouble(),
              );
            }(),
        ];
        notifyListeners();
      case 'env_request':
        envRequests = [
          ...envRequests,
          (m['id'] as String, m['session_id'] as String, m['name'] as String),
        ];
        notifyListeners();
      case 'env_request_resolved':
        envRequests = envRequests.where((r) => r.$1 != m['id']).toList();
        notifyListeners();
      case 'session_message':
        messages = [
          ...messages.length >= 5
              ? messages.sublist(messages.length - 4)
              : messages,
          (m['from'] as String, m['to'] as String, m['body'] as String),
        ];
        notifyListeners();
      case 'projects':
        projects = (m['projects'] as List).cast<Map<String, dynamic>>();
        notifyListeners();
      case 'plans':
        plans = (m['plans'] as List).cast<Map<String, dynamic>>();
        notifyListeners();
      case 'plan_run':
        planRuns[m['plan_id'] as String] = (m['cards'] as List)
            .cast<Map<String, dynamic>>();
        notifyListeners();
      case 'browser_state':
        browserOf(m['profile'] as String)
          ..open = m['open'] as bool
          ..url = m['url'] as String
          ..notifyListeners();
        notifyListeners();
      case 'browser_frame':
        browserOf(m['profile'] as String)
          ..frame = base64Decode(m['jpeg'] as String)
          ..width = m['width'] as int
          ..height = m['height'] as int
          ..notifyListeners();
      case 'diff':
        diffs[m['session_id'] as String] = (
          m['base'] as String,
          (m['files'] as List).cast<Map<String, dynamic>>(),
        );
        notifyListeners();
      case 'pr':
        prs[m['session_id'] as String] = m['pr'] as Map<String, dynamic>?;
        notifyListeners();
      case 'search_results':
        search = (
          m['query'] as String,
          (m['hits'] as List).cast<Map<String, dynamic>>(),
          m['truncated'] as bool,
        );
        notifyListeners();
      case 'mcp_test':
        mcpTests[m['id'] as String] = (
          m['ok'] as bool,
          m['tools'] as int,
          m['error'] as String?,
        );
        notifyListeners();
      case 'error':
        // A slow client missed diffs: ask for full screens again.
        if (m['message'] == 'lagged') {
          for (final id in grids.keys) {
            send({'type': 'snapshot', 'session_id': id});
          }
        } else {
          error = m['message'] as String;
          notifyListeners();
        }
      case 'link_closed':
        _link = null;
        _sub?.cancel();
        _fail(m['reason'] as String);
        _scheduleRetry();
    }
  }

  /// Tests capture outgoing messages here instead of the link.
  @visibleForTesting
  void Function(Map<String, Object?>)? sendHook;

  void send(Map<String, Object?> msg) {
    final hook = sendHook;
    if (hook != null) return hook(msg);
    _link?.send(json: jsonEncode(msg));
  }

  void createSession(
    String accountId, {
    String? cwd,
    Map<String, Object?> profile = const {},
  }) => send({
    'type': 'create_session',
    'account_id': accountId,
    'cwd': cwd,
    'profile': profile,
    'cols': 100,
    'rows': 30,
  });

  void applyProfile(String sessionId, Map<String, Object?> profile) => send({
    'type': 'apply_profile',
    'session_id': sessionId,
    'profile': profile,
  });

  void stop(String sessionId) =>
      send({'type': 'stop_session', 'session_id': sessionId});

  void input(String sessionId, String data) =>
      send({'type': 'input', 'session_id': sessionId, 'data': data});

  void resize(String sessionId, int cols, int rows) => send({
    'type': 'resize',
    'session_id': sessionId,
    'cols': cols,
    'rows': rows,
  });

  void _fail(String message) {
    status = LinkStatus.disconnected;
    error = message;
    notifyListeners();
  }

  void _scheduleRetry() {
    _retry?.cancel();
    if (_disposed || _identity == null) return;
    _retry = Timer(const Duration(seconds: 3), connect);
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
