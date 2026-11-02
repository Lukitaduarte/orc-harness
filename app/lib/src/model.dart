// Domain model shared by the mock store (phase 0) and, later, the daemon client.

enum CatalogKind { skill, mcp, env }

class CatalogItem {
  const CatalogItem(
    this.id,
    this.kind,
    this.name,
    this.description, {
    this.detail = '',
  });

  final String id;
  final CatalogKind kind;
  final String name;
  final String description;

  /// MCP: command or URL. Env: where the value lives (never the value).
  final String detail;
}

enum McpCheck { untested, testing, ok, failed }

class Workspace {
  const Workspace(this.id, this.name, this.initials);

  final String id;
  final String name;
  final String initials;
}

/// One rate-limit window (5h or 7d), as reported by Claude Code's statusLine
/// `rate_limits` object: percentage used and the reset time.
class QuotaWindow {
  const QuotaWindow({
    required this.usedPercent,
    required this.resetsAt,
    required this.burnPerHour,
  });

  final double usedPercent;
  final DateTime resetsAt;

  /// Recent consumption rate, in percentage points per hour (from history).
  final double burnPerHour;

  /// Time until the window is exhausted at the current pace, or null when the
  /// window resets first.
  Duration? timeToExhaust(DateTime now) {
    if (burnPerHour <= 0) return null;
    final hoursLeft = (100 - usedPercent) / burnPerHour;
    final exhaustAt = now.add(Duration(minutes: (hoursLeft * 60).round()));
    return exhaustAt.isBefore(resetsAt) ? exhaustAt.difference(now) : null;
  }
}

class Account {
  const Account({
    required this.id,
    required this.workspaceId,
    required this.email,
    required this.plan,
    required this.fiveHour,
    required this.sevenDay,
    required this.readAt,
  });

  final String id;
  final String workspaceId;
  final String email;
  final String plan;
  final QuotaWindow fiveHour;
  final QuotaWindow sevenDay;

  /// When the last `rate_limits` reading arrived; shown when the account is idle.
  final DateTime readAt;
}

enum SessionState { starting, running, waitingInput, idle }

enum LineKind { prompt, assistant, tool, result, dim }

class TerminalLine {
  const TerminalLine(this.kind, this.text);

  final LineKind kind;
  final String text;
}

class Session {
  Session({
    required this.id,
    required this.workspaceId,
    required this.accountId,
    required this.name,
    required this.branch,
    required this.model,
    required this.state,
    required this.tokens,
    required this.costUsd,
    required this.fiveHourShare,
    required Set<String> enabledItems,
    required this.lines,
  }) : appliedItems = Set.of(enabledItems),
       draftItems = Set.of(enabledItems);

  final String id;
  final String workspaceId;
  final String accountId;
  final String name;
  final String branch;
  final String model;
  SessionState state;
  final int tokens;
  final double costUsd;

  /// This session's share of its account's 5h window, in percentage points.
  final double fiveHourShare;

  /// Catalog items the running process was started with.
  Set<String> appliedItems;

  /// Catalog items checked in the profile panel; applied by restarting the
  /// process with `--resume`.
  Set<String> draftItems;

  final List<TerminalLine> lines;

  bool get hasPendingChanges =>
      appliedItems.length != draftItems.length ||
      !appliedItems.containsAll(draftItems);
}

/// Pane layout: a tree of splits, like tmux. Leaves show one session, or a
/// session picker when [LayoutLeaf.sessionId] is null.
sealed class LayoutNode {
  const LayoutNode(this.id);

  final String id;
}

class LayoutSplit extends LayoutNode {
  const LayoutSplit(super.id, this.horizontal, this.children);

  /// True when children sit side by side.
  final bool horizontal;
  final List<LayoutNode> children;
}

class LayoutLeaf extends LayoutNode {
  const LayoutLeaf(super.id, this.sessionId);

  final String? sessionId;
}

/// Stored state of a project card. "Ready" and "blocked" are derived from the
/// dependency graph, never stored.
enum CardState { todo, running, review, done }

/// Kanban column, derived from [CardState] plus the dependency graph.
enum KanbanColumn { blocked, ready, running, review, done }

class TaskCard {
  TaskCard({
    required this.number,
    required this.title,
    required this.type,
    required this.model,
    this.dependsOn = const [],
    this.state = CardState.todo,
    this.sessionId,
    this.pr,
    this.description = '',
    this.criteria = const [],
    List<Comment>? notes,
  }) : notes = notes ?? [];

  final int number;
  final String title;

  /// Conventional commit type: feat, fix, chore, test, docs.
  final String type;
  final String model;
  final List<int> dependsOn;
  CardState state;
  String? sessionId;
  int? pr;
  final String description;

  /// Acceptance criteria; the card is done when all hold.
  final List<String> criteria;

  /// Comments and notes on the card, from people and agents.
  final List<Comment> notes;

  String get branch => '$type/$number-${_slug(title)}';
}

const _plain = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e', 'ê': 'e', //
  'í': 'i', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ç': 'c',
};

/// Lowercase without Portuguese accents: "Sessões" becomes "sessoes".
String foldAccents(String s) =>
    s.toLowerCase().split('').map((ch) => _plain[ch] ?? ch).join();

String _slug(String s) => foldAccents(
  s,
).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

class Project {
  Project({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.repo,
    required this.cards,
    this.plan,
  });

  final String id;
  final String workspaceId;
  final String name;
  final String repo;
  final List<TaskCard> cards;

  /// Set while the project is being planned; cleared when the plan is
  /// approved and its proposed cards move to the board.
  Plan? plan;

  bool get isPlanning => plan != null;

  TaskCard card(int number) => cards.firstWhere((c) => c.number == number);

  KanbanColumn columnOf(TaskCard c) => switch (c.state) {
    CardState.running => KanbanColumn.running,
    CardState.review => KanbanColumn.review,
    CardState.done => KanbanColumn.done,
    CardState.todo =>
      c.dependsOn.every((d) => card(d).state == CardState.done)
          ? KanbanColumn.ready
          : KanbanColumn.blocked,
  };

  int get doneCount => cards.where((c) => c.state == CardState.done).length;
}

class Comment {
  Comment(this.author, this.body, this.at);

  /// 'Você' or an agent name such as 'Claude'.
  final String author;
  final String body;
  final DateTime at;

  bool get byAgent => author != 'Você';
}

/// Comments on one part of a plan. [anchor] is a section key or `card-<n>`.
class CommentThread {
  CommentThread(this.id, this.anchor, this.anchorLabel, this.messages);

  final String id;
  final String anchor;
  final String anchorLabel;
  final List<Comment> messages;
  bool resolved = false;

  /// Open and still waiting for the agent to answer.
  bool get awaitingAgent => !resolved && !messages.last.byAgent;
}

class PlanBox {
  const PlanBox(this.name, this.detail);

  final String name;
  final String detail;
}

/// Output of plan mode: what will be built and the cards that build it.
class Plan {
  Plan({
    required this.summary,
    required this.architecture,
    required this.folders,
    required this.stack,
    required this.proposedCards,
    List<CommentThread>? threads,
  }) : threads = threads ?? [];

  final String summary;

  /// Components in data-flow order, drawn left to right.
  final List<PlanBox> architecture;
  final String folders;
  final List<(String layer, String choice)> stack;
  final List<TaskCard> proposedCards;
  final List<CommentThread> threads;
  int version = 1;
  bool reviewing = false;

  List<CommentThread> threadsOn(String anchor) =>
      threads.where((t) => t.anchor == anchor).toList();

  int get openThreads => threads.where((t) => !t.resolved).length;
}
