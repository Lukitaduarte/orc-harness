import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mock_data.dart' as mock;
import 'model.dart';

/// App state for phase 0, seeded with fake data. In phase 1 the seeds and the
/// simulated restart give way to the daemon; the screens keep reading this.
class HarnessStore extends ChangeNotifier {
  HarnessStore() : now = DateTime.now() {
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

  List<Workspace> get workspaces => mock.workspaces;

  /// Global catalog, configured once and enabled per session.
  final List<CatalogItem> catalog = [...mock.catalog];
  final mcpChecks = <String, McpCheck>{};

  /// The catalog screen replaces the panes while open.
  bool catalogOpen = false;

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
    if (openProjectId != null || catalogOpen) {
      openProjectId = null;
      catalogOpen = false;
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
    viewingPlan = false;
    notifyListeners();
  }

  void setViewingPlan(bool value) {
    viewingPlan = value;
    notifyListeners();
  }

  void openCatalog() {
    openProjectId = null;
    catalogOpen = true;
    notifyListeners();
  }

  void addCatalogItem(
    CatalogKind kind,
    String name,
    String description,
    String detail,
  ) {
    catalog.add(
      CatalogItem(_nextId('item'), kind, name, description, detail: detail),
    );
    notifyListeners();
  }

  void removeCatalogItem(CatalogItem item) {
    catalog.remove(item);
    for (final s in sessions) {
      s.appliedItems.remove(item.id);
      s.draftItems.remove(item.id);
    }
    notifyListeners();
  }

  /// Simulates the daemon starting the MCP and listing its tools.
  void testMcp(CatalogItem item) {
    mcpChecks[item.id] = McpCheck.testing;
    notifyListeners();
    _later(const Duration(milliseconds: 900), () {
      // linear's token is expired in the mock, to show the failure state.
      mcpChecks[item.id] = item.id == 'linear' ? McpCheck.failed : McpCheck.ok;
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

  /// "Novo plano": the planning session reads the sources, then drafts every
  /// section (simulated).
  Project createPlan(String name, String description, List<String> links) {
    final p = Project(
      id: _nextId('plano'),
      workspaceId: workspaceId,
      name: name,
      repo: 'a definir',
      cards: [],
      plan: mock.draftPlan(name, description, links),
    );
    projects.add(p);
    openProjectView(p.id);
    _later(const Duration(milliseconds: 1800), () {
      mock.fillDraft(p.plan!, name);
      notifyListeners();
    });
    return p;
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
