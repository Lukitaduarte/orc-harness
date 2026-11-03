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
    this.hasReading = true,
    this.live = false,
  });

  /// An account of the daemon (not demo data).
  final bool live;

  final String id;
  final String workspaceId;
  final String email;
  final String plan;
  final QuotaWindow fiveHour;
  final QuotaWindow sevenDay;

  /// When the last `rate_limits` reading arrived; shown when the account is idle.
  final DateTime readAt;

  /// False until Claude Code reported rate limits for this account (they
  /// come only for subscribers, after the first API response).
  final bool hasReading;
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
    this.live = false,
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

  /// A real session in the daemon; its terminal is the live grid.
  final bool live;

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
    this.tasks = const [],
    List<String>? delivered,
    List<String>? problems,
    Map<String, String>? gates,
  }) : notes = notes ?? [],
       delivered = delivered ?? [],
       problems = problems ?? [],
       gates = gates ?? {};

  final int number;
  final String title;

  /// Conventional commit type: feat, fix, chore, test, docs.
  final String type;
  final String model;
  final List<int> dependsOn;
  CardState state;
  String? sessionId;
  int? pr;
  String? prUrl;

  /// Why a live card is not moving (did not start, or its session ended
  /// without a PR); it can be retried.
  String? halt;
  final String description;

  /// Acceptance criteria; the card is done when all hold.
  final List<String> criteria;

  /// Comments and notes on the card, from people and agents.
  final List<Comment> notes;

  /// A card is one PR-sized loop; its tasks run as subagents inside the
  /// card's session, group by group.
  final List<CardTask> tasks;

  /// Results reported by the loop: what landed, what went wrong, and the
  /// gates (analyze, unit, coverage, android, ios) with their outcome.
  final List<String> delivered;
  final List<String> problems;
  final Map<String, String> gates;

  /// Notes already turned into learnings.
  int learnedNotes = 0;

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
    this.live = false,
  });

  /// A plan kept by the daemon (not demo data).
  final bool live;

  final String id;
  final String workspaceId;
  final String name;
  final String repo;
  final List<TaskCard> cards;

  /// The project's plan. While not started it is the project's whole view;
  /// once started its loops are the board's cards and it stays readable.
  Plan? plan;

  bool get isPlanning => plan != null && plan!.startedAt == null;

  /// Skill changes proposed by Learn from the comments on the cards.
  final List<Learning> learnings = [];

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

class CardTask {
  const CardTask(
    this.id,
    this.title, {
    required this.skill,
    required this.model,
    required this.group,
    this.dependsOn = const [],
    this.needsOk = false,
  });

  final String id;
  final String title;

  /// Skill that owns the deliverable; the subagent opens its references.
  final String skill;
  final String model;

  /// Tasks of the same group start together; the next group waits.
  final int group;
  final List<String> dependsOn;

  /// Outward-facing step (production deploy): waits for your OK even with
  /// the plan approved and execution started.
  final bool needsOk;
}

/// Content of a plan section, rendered by type (generative UI, the agent
/// fills the data).
sealed class PlanBlock {
  const PlanBlock();

  /// Text the approval digest is computed over.
  String get text;
}

class TextBlock extends PlanBlock {
  const TextBlock(this.text);

  @override
  final String text;
}

class BulletsBlock extends PlanBlock {
  const BulletsBlock(this.items);

  final List<String> items;

  @override
  String get text => items.join('\n');
}

class TableBlock extends PlanBlock {
  const TableBlock(this.headers, this.rows);

  final List<String> headers;
  final List<List<String>> rows;

  @override
  String get text => [headers, ...rows].map((r) => r.join('|')).join('\n');
}

class CodeBlock extends PlanBlock {
  const CodeBlock(this.caption, this.code);

  final String caption;
  final String code;

  @override
  String get text => '$caption\n$code';
}

enum NodeKind { component, store, external, decision }

class DiagramNode {
  const DiagramNode(
    this.id,
    this.label, {
    this.detail = '',
    this.kind = NodeKind.component,
    this.group,
    this.isNew = false,
  });

  final String id;
  final String label;
  final String detail;
  final NodeKind kind;

  /// Id of the [DiagramGroup] (subgraph) the node belongs to.
  final String? group;

  /// Created by this feature; drawn with the accent.
  final bool isNew;
}

class DiagramEdge {
  const DiagramEdge(
    this.from,
    this.to, {
    this.label = '',
    this.failure = false,
    this.taken = false,
  });

  final String from;
  final String to;
  final String label;

  /// Failure branch: dashed, in the destructive color.
  final bool failure;

  /// Path actually taken, in a decision tree: drawn with the accent.
  final bool taken;
}

class DiagramGroup {
  const DiagramGroup(this.id, this.label);

  final String id;
  final String label;
}

/// A flowchart (Mermaid `flowchart` in the skill), laid out in layers by
/// the app. [vertical] = TB, otherwise LR.
class FlowchartBlock extends PlanBlock {
  const FlowchartBlock({
    required this.nodes,
    required this.edges,
    this.groups = const [],
    this.vertical = true,
    this.caption = '',
  });

  final List<DiagramNode> nodes;
  final List<DiagramEdge> edges;
  final List<DiagramGroup> groups;
  final bool vertical;
  final String caption;

  @override
  String get text => [
    caption,
    ...nodes.map((n) => '${n.id}:${n.label}:${n.detail}:${n.group}'),
    ...edges.map((e) => '${e.from}>${e.to}:${e.label}:${e.failure}'),
  ].join('\n');
}

class SequenceMessage {
  const SequenceMessage(this.from, this.to, this.label, {this.reply = false});

  final String from;
  final String to;
  final String label;

  /// A return message: dashed.
  final bool reply;
}

/// A frame over a run of messages, like `alt falha` in Mermaid.
class SequenceFrame {
  const SequenceFrame(this.label, this.first, this.last);

  final String label;
  final int first;
  final int last;
}

/// A sequence diagram (Mermaid `sequenceDiagram` in the skill).
class SequenceBlock extends PlanBlock {
  const SequenceBlock({
    required this.participants,
    required this.messages,
    this.frames = const [],
    this.caption = '',
  });

  final List<String> participants;
  final List<SequenceMessage> messages;
  final List<SequenceFrame> frames;
  final String caption;

  @override
  String get text => [
    caption,
    participants.join(','),
    ...messages.map((m) => '${m.from}>${m.to}:${m.label}:${m.reply}'),
    ...frames.map((f) => '${f.label}:${f.first}-${f.last}'),
  ].join('\n');
}

/// Renders the plan's loops (its proposed cards) with their tasks.
class LoopsBlock extends PlanBlock {
  const LoopsBlock(this.loops);

  final List<TaskCard> loops;

  @override
  String get text => loops
      .map(
        (l) =>
            '${l.number}:${l.title}:${l.dependsOn}:'
            '${l.tasks.map((t) => '${t.id}/${t.skill}/${t.model}/${t.group}').join(',')}',
      )
      .join('\n');
}

class PlanSection {
  PlanSection(this.id, this.title, this.blocks);

  final String id;
  final String title;
  List<PlanBlock> blocks;

  /// What the planning agent must write here, from the template.
  String instruction = '';

  /// Digest of the content when it was approved. Approval is final.
  String? approvedDigest;
  DateTime? approvedAt;

  bool get approved => approvedDigest != null;

  /// FNV-1a over the section's text, like the create-feature skill.
  String get digest {
    var h = 0x811c9dc5;
    for (final unit in blocks.map((b) => b.text).join('\n').codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  /// An approved section whose content changed: blocks execution.
  bool get changedAfterApproval => approved && digest != approvedDigest;
}

/// A link the plan was built from.
class PlanSource {
  const PlanSource(this.kind, this.url);

  /// Jira, Confluence, Figma or Link.
  final String kind;
  final String url;

  static PlanSource fromUrl(String url) => PlanSource(
    url.contains('atlassian.net/browse') || url.contains('/jira/')
        ? 'Jira'
        : url.contains('atlassian.net/wiki') || url.contains('confluence')
        ? 'Confluence'
        : url.contains('figma.com')
        ? 'Figma'
        : 'Link',
    url,
  );
}

/// Output of plan mode: sections approved one by one, then executed as
/// PR-sized loops (the proposed cards).
class Plan {
  Plan({
    required this.summary,
    required this.sources,
    required this.sections,
    required this.proposedCards,
    List<CommentThread>? threads,
  }) : threads = threads ?? [];

  final String summary;
  final List<PlanSource> sources;
  final List<PlanSection> sections;
  final List<TaskCard> proposedCards;
  final List<CommentThread> threads;

  /// Requests on approved sections, carried into the first loop's notes.
  final List<String> amendments = [];
  int version = 1;
  bool reviewing = false;

  /// True while the agent is still reading the sources (new plans).
  bool drafting = false;
  DateTime? startedAt;

  /// Live: the Claude session writing this plan, while it lives.
  String? plannerSession;

  PlanSection section(String id) => sections.firstWhere((s) => s.id == id);

  List<CommentThread> threadsOn(String anchor) =>
      threads.where((t) => t.anchor == anchor).toList();

  int get openThreads => threads.where((t) => !t.resolved).length;
  int get approvedCount => sections.where((s) => s.approved).length;

  /// Start needs every section approved and none changed since.
  bool get canStart =>
      !drafting && sections.every((s) => s.approved && !s.changedAfterApproval);
}

/// A skill change proposed by Learn; applied only after your OK.
class Learning {
  Learning({
    required this.skill,
    required this.file,
    required this.summary,
    required this.source,
  });

  final String skill;
  final String file;
  final String summary;
  final String source;

  /// null while waiting for your decision.
  bool? accepted;
}

/// A plan mode template: a markdown file with the sections a kind of work
/// needs (deploy for back end, release for apps) and, in each, the
/// instruction for the planning agent plus example content.
class PlanTemplate {
  PlanTemplate(this.id, this.name, this.description, this.markdown);

  final String id;
  String name;
  String description;
  String markdown;
}

/// One row of usage: a day, an account, a model (daemon's UsageRow).
class UsageRow {
  const UsageRow(
    this.day,
    this.accountId,
    this.model,
    this.tokens,
    this.costUsd, {
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheCreation = 0,
    this.projectId,
    this.branch,
  });

  /// Tokens by type (they add up to [tokens]).
  final int input;
  final int output;
  final int cacheRead;
  final int cacheCreation;

  /// Set for sessions in a project worktree; a branch is a plan's card.
  final String? projectId;
  final String? branch;

  /// YYYY-MM-DD, UTC.
  final String day;
  final String accountId;
  final String model;
  final int tokens;
  final double costUsd;
}
