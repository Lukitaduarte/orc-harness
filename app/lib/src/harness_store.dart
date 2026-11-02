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
  final _layouts = <String, LayoutNode>{};
  final _focusedLeaf = <String, String>{};
  int _ids = 0;

  String workspaceId = mock.workspaces.first.id;
  bool profilePanelOpen = true;

  List<Workspace> get workspaces => mock.workspaces;
  List<CatalogItem> get catalog => mock.catalog;

  Workspace get workspace => workspaces.firstWhere((w) => w.id == workspaceId);
  LayoutNode get layout => _layouts[workspaceId]!;
  String get focusedLeafId => _focusedLeaf[workspaceId]!;

  List<Account> get workspaceAccounts =>
      accounts.where((a) => a.workspaceId == workspaceId).toList();
  List<Session> get workspaceSessions =>
      sessions.where((s) => s.workspaceId == workspaceId).toList();

  Account account(String id) => accounts.firstWhere((a) => a.id == id);
  Session session(String id) => sessions.firstWhere((s) => s.id == id);

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
    Timer(const Duration(milliseconds: 1200), () {
      s.state = previous == SessionState.starting
          ? SessionState.idle
          : previous;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _clock.cancel();
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
