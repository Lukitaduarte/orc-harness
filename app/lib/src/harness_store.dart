import 'dart:async';

import 'package:flutter/foundation.dart';

import 'live/daemon_client.dart';

import 'mock_data.dart' as mock;
import 'model.dart';
import 'plan_markdown.dart';
import 'plan_templates.dart';

/// App state for phase 0, seeded with fake data. In phase 1 the seeds and the
/// simulated restart give way to the daemon; the screens keep reading this.
class HarnessStore extends ChangeNotifier {
  HarnessStore({this.daemon}) : now = DateTime.now() {
    daemon?.addListener(_syncLive);
    accounts = mock.seedAccounts(now);
    sessions = mock.seedSessions();
    projects = mock.seedProjects(now);
    for (final ws in mock.workspaces) {
      _layouts[ws.id] = mock.seedLayout(ws.id);
      _focusedLeaf[ws.id] = _firstLeaf(_layouts[ws.id]!).id;
    }
    // Drives reset countdowns and "updated X ago" labels.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      now = DateTime.now();
      notifyListeners();
    });
  }

  late final Timer _clock;
  DateTime now;
  late final List<Account> accounts;
  late final List<Session> sessions;
  late final List<Project> projects;
  final _layouts = <String, LayoutNode>{};
  final _focusedLeaf = <String, String>{};
  int _ids = 0;

  String workspaceId = mock.workspaces.first.id;
  bool profilePanelOpen = true;

  /// Project whose kanban replaces the panes; null shows the panes.
  String? openProjectId;

  /// Cards running at once per project; the daemon will derive this from the
  /// remaining quota.
  static const maxRunningCards = 3;

  /// The real daemon, when the app runs against one ("Este Mac").
  final DaemonClient? daemon;

  static const liveWorkspace = Workspace('live', 'Este Mac', 'EM');

  List<Workspace> get workspaces => [
    ...mock.workspaces,
    if (daemon?.paired ?? false) liveWorkspace,
  ];

  bool _attachNextLive = false;

  /// Mirrors the daemon's accounts and sessions into the "Este Mac"
  /// workspace, keeping the pane layout and each session's profile picks.
  void _syncLive() {
    final d = daemon!;
    _liveTesting.removeWhere(d.mcpTests.containsKey);
    _layouts.putIfAbsent(
      liveWorkspace.id,
      () => const LayoutLeaf('p-live', null),
    );
    _focusedLeaf.putIfAbsent(liveWorkspace.id, () => 'p-live');

    accounts.removeWhere((a) => a.workspaceId == liveWorkspace.id);
    for (final id in d.accounts) {
      final q = d.quotas[id];
      accounts.add(
        Account(
          id: id,
          workspaceId: liveWorkspace.id,
          email: id,
          plan: 'Claude',
          fiveHour: QuotaWindow(
            usedPercent: q?.fiveHour ?? 0,
            resetsAt: q?.fiveHourResetsAt ?? now,
            burnPerHour: 0,
          ),
          sevenDay: QuotaWindow(
            usedPercent: q?.sevenDay ?? 0,
            resetsAt: q?.sevenDayResetsAt ?? now,
            burnPerHour: 0,
          ),
          readAt: q?.readAt ?? now,
          hasReading: q != null,
        ),
      );
    }

    final previous = {for (final s in sessions.where((s) => s.live)) s.id: s};
    sessions.removeWhere((s) => s.live);
    String? added;
    for (final l in d.sessions) {
      final before = previous[l.id];
      if (before == null) added = l.id;
      final cwdName =
          l.cwd.split('/').where((p) => p.isNotEmpty).lastOrNull ?? l.id;
      sessions.add(
        Session(
          id: l.id,
          workspaceId: liveWorkspace.id,
          accountId: l.accountId,
          name: cwdName,
          branch: l.cwd,
          model: l.model ?? 'padrão',
          state: switch (l.state) {
            'running' => SessionState.running,
            'waiting_input' => SessionState.waitingInput,
            'starting' => SessionState.starting,
            _ => SessionState.idle,
          },
          tokens: d.usage[l.id]?.$1 ?? 0,
          costUsd: d.usage[l.id]?.$2 ?? 0,
          fiveHourShare: 0,
          enabledItems: before?.appliedItems ?? const {},
          lines: const [],
          live: true,
        )..draftItems = Set.of(before?.draftItems ?? const {}),
      );
    }
    // Panes showing a session that ended become empty.
    final ids = d.sessions.map((s) => s.id).toSet();
    _layouts[liveWorkspace.id] = _clearMissing(
      _layouts[liveWorkspace.id]!,
      ids,
    );
    if (_attachNextLive && added != null) {
      _attachNextLive = false;
      if (workspaceId == liveWorkspace.id) {
        showSession(added);
        return;
      }
    }
    notifyListeners();
  }

  static LayoutNode _clearMissing(LayoutNode n, Set<String> ids) => switch (n) {
    LayoutLeaf() =>
      n.sessionId == null || ids.contains(n.sessionId)
          ? n
          : LayoutLeaf(n.id, null),
    LayoutSplit() => LayoutSplit(n.id, n.horizontal, [
      for (final c in n.children) _clearMissing(c, ids),
    ]),
  };

  /// The profile the daemon runs a session with, from the catalog picks.
  /// The profile the daemon runs a session with, from the catalog picks:
  /// skill folders, MCP configs as stored in the daemon, env names only.
  Map<String, Object?> _profileFor(Session s) {
    final picked = daemon!.catalog.where((e) => s.draftItems.contains(e['id']));
    return {
      'skills': [
        for (final e in picked.where((e) => e['kind'] == 'skill')) e['path'],
      ],
      'mcp_servers': {
        for (final e in picked.where((e) => e['kind'] == 'mcp'))
          e['name']: e['mcp'],
      },
      'env_names': [
        for (final e in picked.where((e) => e['kind'] == 'env')) e['name'],
      ],
      'model': s.model == 'padrão' ? null : s.model,
    };
  }

  /// "Este Mac" is selected: catalog, templates and sessions are real.
  bool get isLive => daemon != null && workspaceId == liveWorkspace.id;

  /// Global catalog, configured once and enabled per session.
  final List<CatalogItem> _mockCatalog = [...mock.catalog];
  final _mockChecks = <String, McpCheck>{};
  final _liveTesting = <String>{};

  List<CatalogItem> get catalog => isLive ? _liveCatalog() : _mockCatalog;

  Map<String, McpCheck> get mcpChecks {
    if (!isLive) return _mockChecks;
    return {
      for (final MapEntry(:key, :value) in daemon!.mcpTests.entries)
        key: value.$1 ? McpCheck.ok : McpCheck.failed,
      for (final id in _liveTesting) id: McpCheck.testing,
    };
  }

  /// Tool count or error of the last real MCP test.
  (bool, int, String?)? mcpResult(String id) =>
      isLive ? daemon!.mcpTests[id] : null;

  List<CatalogItem> _liveCatalog() => [
    for (final e in daemon!.catalog)
      CatalogItem(
        e['id'] as String,
        switch (e['kind']) {
          'skill' => CatalogKind.skill,
          'mcp' => CatalogKind.mcp,
          _ => CatalogKind.env,
        },
        e['name'] as String,
        e['description'] as String? ?? '',
        detail: switch (e['kind']) {
          'skill' => e['path'] as String? ?? '',
          'mcp' => _mcpText(e['mcp']),
          _ =>
            e['has_value'] == true
                ? 'Keychain do daemon · com valor'
                : 'Keychain do daemon · sem valor ainda',
        },
      ),
  ];

  static String _mcpText(Object? mcp) {
    if (mcp is! Map) return '';
    if (mcp['url'] != null) return mcp['url'] as String;
    return [mcp['command'], ...?(mcp['args'] as List?)].join(' ');
  }

  /// "npx -y pkg arg" or "https://…" into a Claude Code mcpServers entry.
  static Map<String, Object?> _mcpConfig(String detail) {
    final d = detail.trim();
    if (d.startsWith('http')) return {'type': 'http', 'url': d};
    final parts = d.split(RegExp(r'\s+'));
    return {'command': parts.first, 'args': parts.skip(1).toList()};
  }

  /// The catalog screen replaces the panes while open.
  bool catalogOpen = false;

  /// The analytics screen replaces the panes while open.
  bool analyticsOpen = false;
  late final List<UsageRow> _mockUsage = mock.seedUsage(now);

  /// Usage rows of the current workspace's accounts.
  List<UsageRow> get usageRows {
    final ids = workspaceAccounts.map((a) => a.id).toSet();
    final rows = isLive ? daemon!.usageRows : _mockUsage;
    return rows.where((r) => ids.contains(r.accountId)).toList();
  }

  void openAnalytics() {
    openProjectId = null;
    catalogOpen = false;
    analyticsOpen = true;
    if (isLive) daemon!.requestUsage(30);
    notifyListeners();
  }

  /// For a project already executing: show its plan instead of the board.
  bool viewingPlan = false;

  Workspace get workspace => workspaces.firstWhere((w) => w.id == workspaceId);
  LayoutNode get layout => _layouts[workspaceId]!;
  String get focusedLeafId => _focusedLeaf[workspaceId]!;

  List<Account> get workspaceAccounts =>
      accounts.where((a) => a.workspaceId == workspaceId).toList();
  List<Session> get workspaceSessions =>
      sessions.where((s) => s.workspaceId == workspaceId).toList();

  Account account(String id) => accounts.firstWhere((a) => a.id == id);
  Session session(String id) => sessions.firstWhere((s) => s.id == id);

  List<Project> get workspaceProjects =>
      projects.where((p) => p.workspaceId == workspaceId).toList();
  Project? get openProject => openProjectId == null
      ? null
      : projects.firstWhere((p) => p.id == openProjectId);

  /// The workspace account with the most room left in its 5h window.
  Account get freestAccount => workspaceAccounts.reduce(
    (a, b) => a.fiveHour.usedPercent <= b.fiveHour.usedPercent ? a : b,
  );

  Session? get focusedSession {
    final leaf = _findLeaf(layout, focusedLeafId);
    return leaf?.sessionId == null ? null : session(leaf!.sessionId!);
  }

  /// Sessions of the current workspace not shown in any pane.
  List<Session> get hiddenSessions {
    final shown = _shownSessionIds(layout);
    return workspaceSessions.where((s) => !shown.contains(s.id)).toList();
  }

  void selectWorkspace(String id) {
    workspaceId = id;
    openProjectId = null;
    catalogOpen = false;
    analyticsOpen = false;
    notifyListeners();
  }

  void toggleProfilePanel() {
    profilePanelOpen = !profilePanelOpen;
    notifyListeners();
  }

  void focusLeaf(String leafId) {
    if (_focusedLeaf[workspaceId] == leafId) return;
    _focusedLeaf[workspaceId] = leafId;
    notifyListeners();
  }

  /// Focuses the pane showing [sessionId], or shows it in the focused pane.
  void showSession(String sessionId) {
    if (openProjectId != null || catalogOpen || analyticsOpen) {
      openProjectId = null;
      catalogOpen = false;
      analyticsOpen = false;
      notifyListeners();
    }
    final leaf = _leafShowing(layout, sessionId);
    if (leaf != null) {
      focusLeaf(leaf.id);
      return;
    }
    attach(focusedLeafId, sessionId);
  }

  void attach(String leafId, String sessionId) {
    _layouts[workspaceId] = _mapLeaf(
      layout,
      leafId,
      (l) => LayoutLeaf(l.id, sessionId),
    );
    _focusedLeaf[workspaceId] = leafId;
    notifyListeners();
  }

  /// Splits [leafId], adding an empty pane next to it (a session picker).
  void split(String leafId, {required bool horizontal}) {
    final added = LayoutLeaf(_nextId('pane'), null);
    _layouts[workspaceId] = _split(layout, leafId, horizontal, added);
    _focusedLeaf[workspaceId] = added.id;
    notifyListeners();
  }

  /// Closes a pane. The last pane is never removed, only emptied.
  void close(String leafId) {
    final root = layout;
    if (root is LayoutLeaf) {
      _layouts[workspaceId] = LayoutLeaf(root.id, null);
    } else {
      _layouts[workspaceId] = _remove(root, leafId)!;
      if (_findLeaf(layout, focusedLeafId) == null) {
        _focusedLeaf[workspaceId] = _firstLeaf(layout).id;
      }
    }
    notifyListeners();
  }

  void newSession() {
    if (workspaceId == liveWorkspace.id) {
      final d = daemon;
      if (d == null || d.accounts.isEmpty) return;
      _attachNextLive = true;
      d.createSession(d.accounts.first);
      return;
    }
    final acc = workspaceAccounts.first;
    final id = _nextId('sessao');
    sessions.add(
      Session(
        id: id,
        workspaceId: workspaceId,
        accountId: acc.id,
        name: id,
        branch: 'main',
        model: 'sonnet',
        state: SessionState.idle,
        tokens: 0,
        costUsd: 0,
        fiveHourShare: 0,
        enabledItems: const {'conventional-commits'},
        lines: const [
          TerminalLine(LineKind.dim, '✻ Sessão nova. O que vamos fazer?'),
        ],
      ),
    );
    showSession(id);
  }

  void openProjectView(String? projectId) {
    openProjectId = projectId;
    catalogOpen = false;
    analyticsOpen = false;
    viewingPlan = false;
    notifyListeners();
  }

  void setViewingPlan(bool value) {
    viewingPlan = value;
    notifyListeners();
  }

  void openCatalog() {
    openProjectId = null;
    analyticsOpen = false;
    catalogOpen = true;
    notifyListeners();
  }

  void addCatalogItem(
    CatalogKind kind,
    String name,
    String description,
    String detail, {
    String? secretValue,
  }) {
    if (isLive) {
      final kindName = switch (kind) {
        CatalogKind.skill => 'skill',
        CatalogKind.mcp => 'mcp',
        CatalogKind.env => 'env',
      };
      daemon!.send({
        'type': 'upsert_catalog',
        'entry': {
          'id':
              '$kindName-${foldAccents(name).replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
          'kind': kindName,
          'name': name,
          'description': description,
          'path': kind == CatalogKind.skill ? detail.trim() : null,
          'mcp': kind == CatalogKind.mcp ? _mcpConfig(detail) : null,
        },
      });
      // The value goes straight to the daemon's Keychain; the app keeps
      // nothing.
      if (kind == CatalogKind.env &&
          secretValue != null &&
          secretValue.isNotEmpty) {
        daemon!.send({
          'type': 'set_secret',
          'name': name,
          'value': secretValue,
        });
      }
      return;
    }
    _mockCatalog.add(
      CatalogItem(_nextId('item'), kind, name, description, detail: detail),
    );
    notifyListeners();
  }

  void removeCatalogItem(CatalogItem item) {
    if (isLive) {
      daemon!.send({'type': 'remove_catalog', 'id': item.id});
      if (item.kind == CatalogKind.env) {
        daemon!.send({'type': 'delete_secret', 'name': item.name});
      }
    } else {
      _mockCatalog.remove(item);
    }
    for (final s in sessions) {
      s.appliedItems.remove(item.id);
      s.draftItems.remove(item.id);
    }
    notifyListeners();
  }

  /// Live: the daemon starts the MCP and lists its tools. Mock: simulated.
  void testMcp(CatalogItem item) {
    if (isLive) {
      daemon!.mcpTests.remove(item.id);
      _liveTesting.add(item.id);
      daemon!.send({'type': 'test_mcp', 'id': item.id});
      notifyListeners();
      return;
    }
    _mockChecks[item.id] = McpCheck.testing;
    notifyListeners();
    _later(const Duration(milliseconds: 900), () {
      // linear's token is expired in the mock, to show the failure state.
      _mockChecks[item.id] = item.id == 'linear'
          ? McpCheck.failed
          : McpCheck.ok;
      notifyListeners();
    });
  }

  // Plan mode.

  void comment(Plan plan, String anchor, String anchorLabel, String body) {
    plan.threads.add(
      CommentThread(_nextId('thread'), anchor, anchorLabel, [
        Comment('Você', body, DateTime.now()),
      ]),
    );
    notifyListeners();
  }

  void reply(CommentThread t, String body) {
    t.messages.add(Comment('Você', body, DateTime.now()));
    t.resolved = false;
    notifyListeners();
  }

  void setResolved(CommentThread t, bool resolved) {
    t.resolved = resolved;
    notifyListeners();
  }

  /// Approval is final: the section's digest is recorded and any later
  /// change to it blocks execution.
  void approveSection(PlanSection section) {
    if (section.approved) return;
    section
      ..approvedDigest = section.digest
      ..approvedAt = DateTime.now();
    notifyListeners();
  }

  /// Asks the planning agent to address every comment waiting on it.
  /// A comment on an open section revises it; one on an approved section
  /// never edits it and becomes an amendment for the first loop.
  /// Simulated: the daemon will send the comments to the planning session.
  void requestPlanReview(Plan plan) {
    final pending = plan.threads.where((t) => t.awaitingAgent).toList();
    if (pending.isEmpty || plan.reviewing) return;
    plan.reviewing = true;
    notifyListeners();
    _later(const Duration(milliseconds: 1500), () {
      final version = plan.version + 1;
      for (final t in pending) {
        final ask = t.messages.last.body;
        final section = plan.section(t.anchor);
        if (section.approved) {
          plan.amendments.add('${section.title}: $ask');
          t.messages.add(
            Comment(
              'Claude',
              'Essa seção já está aprovada e não muda. Registrei como emenda: '
                  'entra nas notas do primeiro loop.',
              DateTime.now(),
            ),
          );
        } else {
          section.blocks = [
            ...section.blocks,
            TextBlock('Ajuste v$version: $ask'),
          ];
          t.messages.add(
            Comment(
              'Claude',
              'Ajustei ${section.title} na versão $version do plano.',
              DateTime.now(),
            ),
          );
          t.resolved = true;
        }
      }
      plan
        ..version = version
        ..reviewing = false;
      notifyListeners();
    });
  }

  /// "Iniciar execução": the plan's loops become the board's cards and the
  /// ready ones start. Amendments and open comments go to the first loop.
  void startExecution(Project p) {
    final plan = p.plan;
    if (plan == null || !plan.canStart || plan.startedAt != null) return;
    final now = DateTime.now();
    final carried = [
      ...plan.amendments.map((a) => 'Emenda: $a'),
      for (final t in plan.threads.where((t) => !t.resolved))
        'Comentário em ${t.anchorLabel}: ${t.messages.last.body}',
    ];
    p.cards.addAll(plan.proposedCards);
    if (p.cards.isNotEmpty) {
      p.cards.first.notes.addAll(carried.map((c) => Comment('Claude', c, now)));
    }
    plan.startedAt = now;
    runReady(p);
    notifyListeners();
  }

  /// "Novo plano" from a template: the planning session reads the sources
  /// and fills each of the template's sections, following the section's
  /// instruction (simulated: the template's example content is used).
  Project createPlan(
    String name,
    String description,
    List<String> links,
    PlanTemplate template,
  ) {
    final filled = parsePlanMarkdown(template.markdown).plan;
    final plan = Plan(
      summary: description.isEmpty ? name : description,
      sources: links.map(PlanSource.fromUrl).toList(),
      proposedCards: [],
      sections: [
        for (final s in filled.sections)
          PlanSection(s.id, s.title, [
            TextBlock(
              s.instruction.isEmpty
                  ? 'Em elaboração a partir das fontes.'
                  : 'Em elaboração: ${s.instruction}',
            ),
          ])..instruction = s.instruction,
      ],
    )..drafting = true;
    final p = Project(
      id: _nextId('plano'),
      workspaceId: workspaceId,
      name: name,
      repo: 'a definir',
      cards: [],
      plan: plan,
    );
    projects.add(p);
    openProjectView(p.id);
    _later(const Duration(milliseconds: 1800), () {
      for (final (i, s) in plan.sections.indexed) {
        s.blocks = filled.sections[i].blocks;
      }
      plan
        ..proposedCards.addAll(filled.proposedCards)
        ..drafting = false;
      notifyListeners();
    });
    return p;
  }

  /// Opens a plan written elsewhere (any markdown in the plan format) as a
  /// project ready for review.
  Project importPlan(String markdown) {
    final parsed = parsePlanMarkdown(markdown);
    final p = Project(
      id: _nextId('plano'),
      workspaceId: workspaceId,
      name: parsed.title.isEmpty ? 'Plano importado' : parsed.title,
      repo: parsed.repo.isEmpty ? 'a definir' : parsed.repo,
      cards: [],
      plan: parsed.plan,
    );
    projects.add(p);
    openProjectView(p.id);
    return p;
  }

  /// Plan mode templates, one markdown each.
  final List<PlanTemplate> _mockTemplates = [...seedTemplates];

  /// Plan mode templates: the daemon's `~/.orc/templates` when live.
  List<PlanTemplate> get planTemplates => isLive
      ? [
          for (final t in daemon!.templates)
            _templateFromFile(t['id'] as String, t['markdown'] as String),
        ]
      : _mockTemplates;

  /// Name and description come from the file's frontmatter.
  static PlanTemplate _templateFromFile(String id, String markdown) {
    String field(String key) =>
        RegExp(
          '^$key:\\s*(.+)\$',
          multiLine: true,
        ).firstMatch(markdown)?.group(1)?.trim() ??
        '';
    final name = field('name');
    return PlanTemplate(
      id,
      name.isEmpty ? id : name,
      field('description'),
      markdown,
    );
  }

  static String _templateFile(
    String name,
    String description,
    String markdown,
  ) {
    // Replace any frontmatter with one carrying name and description.
    final body = markdown.replaceFirst(RegExp(r'^---\n[\s\S]*?\n---\n'), '');
    return '---\nname: $name\ndescription: $description\n---\n$body';
  }

  PlanTemplate addTemplate(String name, String description, String markdown) {
    if (isLive) {
      final id = foldAccents(name).replaceAll(RegExp(r'[^a-z0-9]+'), '-');
      final file = _templateFile(name, description, markdown);
      daemon!.send({
        'type': 'upsert_template',
        'template': {'id': id, 'markdown': file},
      });
      return PlanTemplate(id, name, description, file);
    }
    final t = PlanTemplate(_nextId('template'), name, description, markdown);
    _mockTemplates.add(t);
    notifyListeners();
    return t;
  }

  void updateTemplate(
    PlanTemplate t, {
    String? name,
    String? description,
    String? markdown,
  }) {
    t
      ..name = name ?? t.name
      ..description = description ?? t.description
      ..markdown = markdown ?? t.markdown;
    if (isLive) {
      daemon!.send({
        'type': 'upsert_template',
        'template': {
          'id': t.id,
          'markdown': _templateFile(t.name, t.description, t.markdown),
        },
      });
    }
    notifyListeners();
  }

  void removeTemplate(PlanTemplate t) {
    if (isLive) {
      daemon!.send({'type': 'remove_template', 'id': t.id});
    } else {
      _mockTemplates.remove(t);
    }
    notifyListeners();
  }

  /// Learn: comments on the cards become proposed skill changes, applied
  /// only after your OK.
  void learn(Project p) {
    for (final c in p.cards) {
      final fresh = c.notes.skip(c.learnedNotes).where((n) => !n.byAgent);
      for (final n in fresh) {
        p.learnings.add(
          Learning(
            skill: c.tasks.isEmpty ? 'create-feature' : c.tasks.first.skill,
            file: 'SKILL.md',
            summary: n.body,
            source: 'Card #${c.number} · comentário',
          ),
        );
      }
      c.learnedNotes = c.notes.length;
    }
    notifyListeners();
  }

  int unlearnedNotes(Project p) => p.cards
      .map((c) => c.notes.skip(c.learnedNotes).where((n) => !n.byAgent).length)
      .fold(0, (a, b) => a + b);

  void decideLearning(Learning l, bool accepted) {
    l.accepted = accepted;
    notifyListeners();
  }

  void addCardNote(TaskCard c, String body) {
    c.notes.add(Comment('Você', body, DateTime.now()));
    notifyListeners();
  }

  List<TaskCard> readyCards(Project p) =>
      p.cards.where((c) => p.columnOf(c) == KanbanColumn.ready).toList();

  int runningCount(Project p) =>
      p.cards.where((c) => c.state == CardState.running).length;

  bool canRun(Project p) => runningCount(p) < maxRunningCards;

  /// Starts a card: worktree + branch + its own session on the account with
  /// the most room, using the card's model.
  void runCard(Project p, TaskCard c) {
    if (p.columnOf(c) != KanbanColumn.ready || !canRun(p)) return;
    final id = _nextId('card');
    sessions.add(
      Session(
        id: id,
        workspaceId: p.workspaceId,
        accountId: freestAccount.id,
        name: '${p.id.split('-').first}#${c.number}',
        branch: c.branch,
        model: c.model,
        state: SessionState.running,
        tokens: 0,
        costUsd: 0,
        fiveHourShare: 0,
        enabledItems: const {'conventional-commits'},
        lines: [
          TerminalLine(
            LineKind.dim,
            '✻ worktree criada em ~/.orc/worktrees/${c.branch}',
          ),
          TerminalLine(LineKind.prompt, '> ${c.title}'),
          const TerminalLine(
            LineKind.dim,
            '✻ Lendo o card e os critérios de aceite…',
          ),
        ],
      ),
    );
    c
      ..state = CardState.running
      ..sessionId = id;
    notifyListeners();
  }

  /// Starts every ready card, up to the concurrency limit.
  void runReady(Project p) {
    for (final c in readyCards(p)) {
      if (!canRun(p)) break;
      runCard(p, c);
    }
  }

  int _nextPr = 20;

  /// Simulation of the agent opening a PR (the daemon reports this later).
  void simulatePr(TaskCard c) {
    c
      ..state = CardState.review
      ..pr = _nextPr++;
    if (c.sessionId != null) session(c.sessionId!).state = SessionState.idle;
    notifyListeners();
  }

  /// Simulation of the PR being merged; dependents become ready.
  void simulateMerge(TaskCard c) {
    c.state = CardState.done;
    notifyListeners();
  }

  void toggleItem(Session s, String itemId) {
    if (!s.draftItems.remove(itemId)) s.draftItems.add(itemId);
    notifyListeners();
  }

  void discardDraft(Session s) {
    s.draftItems = Set.of(s.appliedItems);
    notifyListeners();
  }

  /// Simulates the daemon restarting the process with `--resume`.
  void applyDraft(Session s) {
    if (s.live) {
      // The daemon restarts claude with --resume; state comes back via hooks.
      daemon?.applyProfile(s.id, _profileFor(s));
      s
        ..appliedItems = Set.of(s.draftItems)
        ..state = SessionState.starting;
      notifyListeners();
      return;
    }
    final previous = s.state;
    s.state = SessionState.starting;
    s.appliedItems = Set.of(s.draftItems);
    notifyListeners();
    _later(const Duration(milliseconds: 1200), () {
      s.state = previous == SessionState.starting
          ? SessionState.idle
          : previous;
      notifyListeners();
    });
  }

  /// One-shot timers for simulated daemon events; cancelled on dispose so
  /// none fires into a disposed store.
  final _pending = <Timer>{};

  void _later(Duration delay, VoidCallback f) {
    late final Timer t;
    t = Timer(delay, () {
      _pending.remove(t);
      f();
    });
    _pending.add(t);
  }

  @override
  void dispose() {
    daemon?.removeListener(_syncLive);
    _clock.cancel();
    for (final t in _pending) {
      t.cancel();
    }
    super.dispose();
  }

  String _nextId(String prefix) => '$prefix-${++_ids}';

  static LayoutLeaf _firstLeaf(LayoutNode n) => switch (n) {
    LayoutLeaf() => n,
    LayoutSplit() => _firstLeaf(n.children.first),
  };

  static LayoutLeaf? _findLeaf(LayoutNode n, String id) => switch (n) {
    LayoutLeaf() => n.id == id ? n : null,
    LayoutSplit() =>
      n.children.map((c) => _findLeaf(c, id)).nonNulls.firstOrNull,
  };

  static LayoutLeaf? _leafShowing(LayoutNode n, String sessionId) =>
      switch (n) {
        LayoutLeaf() => n.sessionId == sessionId ? n : null,
        LayoutSplit() =>
          n.children
              .map((c) => _leafShowing(c, sessionId))
              .nonNulls
              .firstOrNull,
      };

  static Set<String> _shownSessionIds(LayoutNode n) => switch (n) {
    LayoutLeaf() => {?n.sessionId},
    LayoutSplit() => {for (final c in n.children) ..._shownSessionIds(c)},
  };

  static LayoutNode _mapLeaf(
    LayoutNode n,
    String id,
    LayoutLeaf Function(LayoutLeaf) f,
  ) => switch (n) {
    LayoutLeaf() => n.id == id ? f(n) : n,
    LayoutSplit() => LayoutSplit(n.id, n.horizontal, [
      for (final c in n.children) _mapLeaf(c, id, f),
    ]),
  };

  LayoutNode _split(
    LayoutNode n,
    String id,
    bool horizontal,
    LayoutLeaf added,
  ) {
    switch (n) {
      case LayoutLeaf():
        return n.id == id
            ? LayoutSplit(_nextId('split'), horizontal, [n, added])
            : n;
      case LayoutSplit():
        final i = n.children.indexWhere((c) => c is LayoutLeaf && c.id == id);
        // Same direction as the parent: add a sibling instead of nesting.
        if (i >= 0 && n.horizontal == horizontal) {
          return LayoutSplit(
            n.id,
            n.horizontal,
            [...n.children]..insert(i + 1, added),
          );
        }
        return LayoutSplit(n.id, n.horizontal, [
          for (final c in n.children) _split(c, id, horizontal, added),
        ]);
    }
  }

  static LayoutNode? _remove(LayoutNode n, String id) {
    switch (n) {
      case LayoutLeaf():
        return n.id == id ? null : n;
      case LayoutSplit():
        final kept = n.children.map((c) => _remove(c, id)).nonNulls.toList();
        if (kept.isEmpty) return null;
        return kept.length == 1
            ? kept.single
            : LayoutSplit(n.id, n.horizontal, kept);
    }
  }
}
