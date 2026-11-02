// Domain model shared by the mock store (phase 0) and, later, the daemon client.

enum CatalogKind { skill, mcp, env }

class CatalogItem {
  const CatalogItem(this.id, this.kind, this.name, this.description);

  final String id;
  final CatalogKind kind;
  final String name;
  final String description;
}

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
