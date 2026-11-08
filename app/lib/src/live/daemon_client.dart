import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../rust/api/link.dart' as link;
import '../i18n.dart';
import '../model.dart';
import 'grid.dart';
import 'local_daemon.dart';
import 'lsp_client.dart';

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
    this.profile,
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
    profile: j['profile'] as Map<String, dynamic>?,
  );

  /// What the session runs with (skills, MCP servers, env names, browser),
  /// as the daemon has it.
  final Map<String, dynamic>? profile;

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
    profile: profile,
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

  /// The session whose agent is driving it now, if any.
  String? usedBy;

  /// Last screen (JPEG) and the page size it shows, in CSS pixels.
  Uint8List? frame;
  int width = 0;
  int height = 0;
}

/// The app's connection to orcd: pairing, connecting (with retry), and the
/// live state it reports. Notifies on session, account and quota changes.
class DaemonClient extends ChangeNotifier {
  DaemonClient({LocalDaemon? local}) : local = local ?? LocalDaemon();

  /// The daemon bundled with the macOS app, set up on first launch.
  final LocalDaemon local;

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

  /// Actions waiting for your OK (deploys, releases, merges): (id,
  /// session, what it wants to do).
  List<(String, String, String)> approvals = [];

  void resolveApproval(String id, bool approve) {
    send({'type': 'resolve_approval', 'id': id, 'approve': approve});
    approvals = approvals.where((a) => a.$1 != id).toList();
    notifyListeners();
  }

  /// MCP servers agents ask to add: (id, session, name, config, reason).
  List<(String, String, String, Map<String, dynamic>, String)> mcpRequests = [];

  /// MCP servers set up in Claude Code that could join the catalog (null
  /// until asked for).
  List<Map<String, dynamic>>? mcpImports;

  void scanMcpImports() {
    mcpImports = null;
    send({'type': 'scan_mcp_imports'});
    notifyListeners();
  }

  /// Brings them in; their secret values go to the Keychain on the daemon.
  void importMcps(List<String> keys) =>
      send({'type': 'import_mcps', 'keys': keys});

  /// Approving adds it to the catalog and restarts that session with it.
  void resolveMcpRequest(String id, bool approve) {
    send({'type': 'resolve_mcp_request', 'id': id, 'approve': approve});
    mcpRequests = mcpRequests.where((r) => r.$1 != id).toList();
    notifyListeners();
  }

  void resolveEnvRequest(String id, bool approve) {
    send({'type': 'resolve_env_request', 'id': id, 'approve': approve});
    envRequests = envRequests.where((r) => r.$1 != id).toList();
    notifyListeners();
  }

  void dismissMessages() {
    messages = [];
    notifyListeners();
  }

  /// Things worth telling you when you are not looking: (title, body).
  /// Set by the app (system notifications); only changes, never replays.
  void Function(String title, String body)? onAlert;

  /// A session as you know it: its branch, else its folder's name.
  String sessionLabel(String id) {
    final s = sessions.where((s) => s.id == id).firstOrNull;
    if (s == null) return id;
    return s.branch ??
        s.cwd.split('/').where((p) => p.isNotEmpty).lastOrNull ??
        id;
  }

  /// Learn proposals by plan (orc_protocol::LearningItem JSON).
  final learnings = <String, List<Map<String, dynamic>>>{};

  void learn(
    String planId,
    String accountId,
    List<String> notes,
    List<String> skills,
  ) => send({
    'type': 'learn',
    'plan_id': planId,
    'account_id': accountId,
    'notes': notes,
    'skills': skills,
  });

  void decideLearning(String planId, String id, bool accept) => send({
    'type': 'decide_learning',
    'plan_id': planId,
    'id': id,
    'accept': accept,
  });

  /// Workspaces (orc_protocol::WorkspaceInfo JSON); empty until reported.
  List<Map<String, dynamic>> workspaces = [];

  void upsertWorkspace(
    String id,
    String name,
    List<String> accounts, {
    String? memory,
    double? budgetUsd,
  }) => send({
    'type': 'upsert_workspace',
    'workspace': {
      'id': id,
      'name': name,
      'accounts': accounts,
      'memory': memory,
      'budget_usd': budgetUsd,
    },
  });

  /// Last commit/push/merge result per session: (action, ok, output).
  final gitResults = <String, (String, bool, String)>{};

  void gitCommit(String sessionId, String message) =>
      send({'type': 'git_commit', 'session_id': sessionId, 'message': message});

  void gitPush(String sessionId) =>
      send({'type': 'git_push', 'session_id': sessionId});

  void mergePr(String sessionId) =>
      send({'type': 'merge_pr', 'session_id': sessionId});

  /// The folder picker: (path, parent, folders as (name, is repo)).
  (String, String?, List<(String, bool)>)? folders;

  void browseFolders(String? path, {bool hidden = false}) =>
      send({'type': 'browse_folders', 'path': path, 'hidden': hidden});

  /// A one-time ticket for pairing another device (shown as a QR), and
  /// when it was issued (valid 10 minutes).
  (String, DateTime)? pairingTicket;

  void requestPairingTicket() => send({'type': 'new_pairing_ticket'});

  /// Paired devices (orc_protocol::DeviceInfo JSON), and which is this one.
  List<Map<String, dynamic>> devices = [];
  String? thisDevice;

  void listDevices() => send({'type': 'list_devices'});

  void revokeDevice(String id) => send({'type': 'revoke_device', 'id': id});

  /// The harness memory of each workspace (orc_protocol::MemoryEntry JSON).
  final memory = <String, List<Map<String, dynamic>>>{};

  void listMemory(String workspaceId) =>
      send({'type': 'list_memory', 'workspace_id': workspaceId});

  void forgetMemory(String workspaceId, String id) =>
      send({'type': 'forget_memory', 'workspace_id': workspaceId, 'id': id});

  void removeWorkspace(String id) =>
      send({'type': 'remove_workspace', 'id': id});

  void addAccount(String id, String workspaceId) =>
      send({'type': 'add_account', 'id': id, 'workspace_id': workspaceId});

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

  /// IDE: folder listings by (session, path), and file reads in flight.
  final dirs = <(String, String), List<Map<String, dynamic>>>{};
  final _reads = <(String, String), Completer<String>>{};

  /// Language servers by (session, language).
  final _lsp = <(String, String), LspClient>{};

  void listDir(String sessionId, String path) =>
      send({'type': 'list_dir', 'session_id': sessionId, 'path': path});

  /// The file's text; fails with the daemon's error.
  Future<String> readFile(String sessionId, String path) {
    final c = _reads[(sessionId, path)] ??= Completer<String>();
    send({'type': 'read_file', 'session_id': sessionId, 'path': path});
    return c.future.timeout(const Duration(seconds: 20));
  }

  void writeFile(String sessionId, String path, String text) => send({
    'type': 'write_file',
    'session_id': sessionId,
    'path': path,
    'text': text,
  });

  void openExternal(String sessionId, String path, String app) => send({
    'type': 'open_external',
    'session_id': sessionId,
    'path': path,
    'app': app,
  });

  /// The session's language server for [language], rooted at its folder.
  LspClient lsp(String sessionId, String language) =>
      _lsp.putIfAbsent((sessionId, language), () {
        final cwd = sessions.firstWhere((s) => s.id == sessionId).cwd;
        return LspClient(
          cwd,
          (message) => send({
            'type': 'lsp',
            'session_id': sessionId,
            'language': language,
            'message': message,
          }),
        );
      });

  /// Last file the daemon saved: (session, path).
  (String, String)? saved;

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

  void addProject(
    String name,
    String repo,
    String base, {
    String? workspaceId,
  }) => send({
    'type': 'add_project',
    'name': name,
    'repo': repo,
    'base_branch': base,
    'workspace_id': workspaceId,
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

  /// Whether a pairing is stored (this app talked to a daemon before).
  Future<bool> hasPairing() async => (await _identityFile()).exists();

  /// Installs the app's own daemon if needed and pairs with it over the
  /// local socket.
  Future<void> pairLocal() async {
    status = LinkStatus.connecting;
    error = null;
    notifyListeners();
    try {
      final ticket = await local.ticket();
      if (ticket != null) await pair(ticket);
    } catch (e) {
      _fail('$e');
    }
  }

  /// Loads a stored pairing and connects. Without one, and with
  /// [autoPair], the app's own daemon is installed and paired with (the
  /// first launch does that step by step, in the onboarding).
  Future<void> start({bool autoPair = true}) async {
    try {
      final f = await _identityFile();
      if (await f.exists()) {
        _identity = await f.readAsString();
        // A new app version brings its daemon along.
        try {
          await local.ensureInstalled(onlyUpdate: true);
        } catch (e) {
          debugPrint('$e');
        }
        await connect();
      } else if (autoPair && local.bundled != null) {
        await pairLocal();
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
        final before = sessions
            .where((s) => s.id == m['session_id'])
            .firstOrNull
            ?.state;
        if (m['state'] == 'waiting_input' && before != 'waiting_input') {
          onAlert?.call(
            l10n.orcNeedDoing,
            l10n.coreAlertWaitingBody(sessionLabel(m['session_id'] as String)),
          );
        }
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
                input: u['input'] as int,
                output: u['output'] as int,
                cacheRead: u['cache_read'] as int,
                cacheCreation: u['cache_creation'] as int,
                projectId: r['project_id'] as String?,
                branch: r['branch'] as String?,
              );
            }(),
        ];
        notifyListeners();
      case 'env_request':
        onAlert?.call(
          l10n.coreAlertEnvTitle,
          l10n.coreAlertEnvBody(
            sessionLabel(m['session_id'] as String),
            '${m['name']}',
          ),
        );
        envRequests = [
          ...envRequests,
          (m['id'] as String, m['session_id'] as String, m['name'] as String),
        ];
        notifyListeners();
      case 'approval':
        final id = m['id'] as String;
        if (!approvals.any((a) => a.$1 == id)) {
          onAlert?.call(
            l10n.coreAlertApprovalTitle,
            '${sessionLabel(m['session_id'] as String)}: ${m['action']}',
          );
          approvals = [
            ...approvals,
            (id, m['session_id'] as String, m['action'] as String),
          ];
          notifyListeners();
        }
      case 'approval_resolved':
        approvals = approvals.where((a) => a.$1 != m['id']).toList();
        notifyListeners();
      case 'mcp_request':
        onAlert?.call(
          l10n.coreAlertMcpTitle,
          l10n.coreAlertMcpBody(
            sessionLabel(m['session_id'] as String),
            '${m['name']}',
          ),
        );
        mcpRequests = [
          ...mcpRequests,
          (
            m['id'] as String,
            m['session_id'] as String,
            m['name'] as String,
            m['mcp'] as Map<String, dynamic>,
            (m['reason'] as String?) ?? '',
          ),
        ];
        notifyListeners();
      case 'mcp_imports':
        mcpImports = (m['items'] as List).cast<Map<String, dynamic>>();
        notifyListeners();
      case 'mcp_request_resolved':
        mcpRequests = mcpRequests.where((r) => r.$1 != m['id']).toList();
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
      case 'learnings':
        learnings[m['plan_id'] as String] = (m['items'] as List)
            .cast<Map<String, dynamic>>();
        notifyListeners();
      case 'git_result':
        final sid = m['session_id'] as String;
        gitResults[sid] = (
          m['action'] as String,
          m['ok'] as bool,
          m['output'] as String,
        );
        // What changed: the files and the PR.
        if (m['ok'] == true) {
          requestDiff(sid);
          send({'type': 'pr_status', 'session_id': sid});
        }
        notifyListeners();
      case 'folders':
        folders = (
          m['path'] as String,
          m['parent'] as String?,
          [
            for (final f in (m['folders'] as List).cast<Map<String, dynamic>>())
              (f['name'] as String, f['repo'] as bool),
          ],
        );
        notifyListeners();
      case 'pairing_ticket':
        pairingTicket = (m['ticket'] as String, DateTime.now());
        notifyListeners();
      case 'devices':
        devices = (m['devices'] as List).cast<Map<String, dynamic>>();
        // Broadcasts after a revoke do not say which one is this.
        thisDevice =
            devices.where((d) => d['this'] == true).firstOrNull?['id']
                as String? ??
            thisDevice;
        notifyListeners();
      case 'memory':
        memory[m['workspace_id'] as String] = (m['entries'] as List)
            .cast<Map<String, dynamic>>();
        notifyListeners();
      case 'workspaces':
        workspaces = (m['workspaces'] as List).cast<Map<String, dynamic>>();
        notifyListeners();
      case 'plans':
        plans = (m['plans'] as List).cast<Map<String, dynamic>>();
        notifyListeners();
      case 'plan_run':
        final id = m['plan_id'] as String;
        final cards = (m['cards'] as List).cast<Map<String, dynamic>>();
        final previous = {
          for (final c in planRuns[id] ?? const <Map<String, dynamic>>[])
            c['number']: c['state'],
        };
        // The first report (on connect) only sets the scene.
        if (planRuns.containsKey(id)) {
          final plan = plans.where((p) => p['id'] == id).firstOrNull;
          final name = plan?['name'] ?? id;
          for (final c in cards) {
            final state = c['state'];
            if (state == previous[c['number']]) continue;
            final msg = switch (state) {
              'review' => (
                l10n.coreAlertPrTitle,
                l10n.coreAlertPrBody('$name', '${c['number']}'),
              ),
              'done' => (
                l10n.orcJobsDone,
                l10n.coreAlertMergedBody('$name', '${c['number']}'),
              ),
              'failed' || 'stopped' => (
                l10n.coreAlertStoppedTitle,
                l10n.coreAlertStoppedBody(
                  '$name',
                  '${c['number']}',
                  '${c['note'] ?? state}',
                ),
              ),
              _ => null,
            };
            if (msg != null) onAlert?.call(msg.$1, msg.$2);
          }
        }
        planRuns[id] = cards;
        notifyListeners();
      case 'dir_entries':
        dirs[(m['session_id'] as String, m['path'] as String)] =
            (m['entries'] as List).cast<Map<String, dynamic>>();
        notifyListeners();
      case 'file_content':
        _reads
            .remove((m['session_id'] as String, m['path'] as String))
            ?.complete(m['text'] as String);
      case 'file_saved':
        saved = (m['session_id'] as String, m['path'] as String);
        notifyListeners();
      case 'lsp':
        _lsp[(m['session_id'] as String, m['language'] as String)]?.handle(
          m['message'] as Map<String, dynamic>,
        );
      case 'browser_state':
        browserOf(m['profile'] as String)
          ..open = m['open'] as bool
          ..url = m['url'] as String
          ..notifyListeners();
        notifyListeners();
      case 'browser_use':
        browserOf(m['profile'] as String)
          ..usedBy = m['session_id'] as String?
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
          // Errors are not tied to a request: a read waiting gets it.
          for (final c in _reads.values) {
            c.completeError(error!);
          }
          _reads.clear();
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

  /// The size this device's view of each session wants.
  final _mySize = <String, (int, int)>{};

  /// A terminal has one size: whoever types gets theirs. If another device
  /// (the phone, the desktop) resized it, this one takes it back first.
  void input(String sessionId, String data) {
    final mine = _mySize[sessionId];
    final g = grids[sessionId]?.state;
    if (mine != null && g != null && g.cols > 0 && (g.cols, g.rows) != mine) {
      _sendResize(sessionId, mine.$1, mine.$2);
    }
    send({'type': 'input', 'session_id': sessionId, 'data': data});
  }

  void resize(String sessionId, int cols, int rows) {
    _mySize[sessionId] = (cols, rows);
    _sendResize(sessionId, cols, rows);
  }

  void _sendResize(String sessionId, int cols, int rows) => send({
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
