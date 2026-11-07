import 'dart:convert';

import '../i18n.dart';
import '../model.dart';
import '../plan_markdown.dart';

/// Plans kept by the daemon (orc_protocol::PlanDoc): the markdown, written
/// by the planning session, plus the review state the app owns, as JSON:
///
/// ```json
/// { "approvals": { "<section>": { "digest": "…", "at": 0 } },
///   "threads": [ { "id", "anchor", "label", "resolved",
///                  "messages": [ { "author", "body", "at" } ] } ],
///   "amendments": [ "…" ], "startedAt": 0,
///   "notes": { "<card>": [ { "author", "body", "at" } ] } }
/// ```
///
/// The daemon appends the agent's replies to `threads` and its amendments
/// to `amendments` (plans::apply_save).

/// Builds the project a plan document shows as. [run] is the daemon's
/// PlanRun cards, if the plan was started.
Project projectFromDoc(
  Map<String, dynamic> doc, {
  required String workspaceId,
  required String repoName,
}) {
  final parsed = parsePlanMarkdown(doc['markdown'] as String? ?? '');
  final plan = parsed.plan;
  final state = (doc['state'] as Map?)?.cast<String, dynamic>() ?? const {};
  final revision = doc['revision'] as int? ?? 0;
  final busy = doc['busy'] as bool? ?? false;

  final approvals = (state['approvals'] as Map?) ?? const {};
  for (final s in plan.sections) {
    final a = approvals[s.id] as Map?;
    if (a == null) continue;
    s
      ..approvedDigest = a['digest'] as String?
      ..approvedAt = _time(a['at']);
  }
  for (final t in (state['threads'] as List?) ?? const []) {
    final m = (t as Map).cast<String, dynamic>();
    plan.threads.add(
      CommentThread(
        m['id'] as String,
        m['anchor'] as String,
        m['label'] as String? ?? '',
        [for (final c in (m['messages'] as List?) ?? const []) _comment(c)],
      )..resolved = m['resolved'] as bool? ?? false,
    );
  }
  plan.amendments.addAll([
    for (final a in (state['amendments'] as List?) ?? const []) '$a',
  ]);
  plan
    ..version = revision + 1
    ..drafting = busy && revision == 0
    ..reviewing = busy && revision > 0
    ..startedAt = _time(state['startedAt'])
    ..plannerSession = doc['planner'] as String?;

  final notes = (state['notes'] as Map?) ?? const {};
  final learned = (state['learned'] as Map?) ?? const {};
  for (final c in plan.proposedCards) {
    c.notes.addAll([
      for (final n in (notes['${c.number}'] as List?) ?? const []) _comment(n),
    ]);
    c.learnedNotes = learned['${c.number}'] as int? ?? 0;
  }
  return Project(
    id: doc['id'] as String,
    workspaceId: workspaceId,
    name: doc['name'] as String? ?? parsed.title,
    repo: repoName,
    cards: plan.startedAt == null ? [] : plan.proposedCards,
    plan: plan,
    live: true,
  );
}

/// The review state of [p], as the daemon stores it.
Map<String, Object?> planState(Project p) {
  final plan = p.plan!;
  return {
    'approvals': {
      for (final s in plan.sections.where((s) => s.approved))
        s.id: {
          'digest': s.approvedDigest,
          'at': s.approvedAt?.millisecondsSinceEpoch,
        },
    },
    'threads': [
      for (final t in plan.threads)
        {
          'id': t.id,
          'anchor': t.anchor,
          'label': t.anchorLabel,
          'resolved': t.resolved,
          'messages': t.messages.map(_commentJson).toList(),
        },
    ],
    'amendments': plan.amendments,
    'startedAt': plan.startedAt?.millisecondsSinceEpoch,
    'notes': {
      for (final c in plan.proposedCards.where((c) => c.notes.isNotEmpty))
        '${c.number}': c.notes.map(_commentJson).toList(),
    },
    // Comments already sent to Learn, per card.
    'learned': {
      for (final c in plan.proposedCards.where((c) => c.learnedNotes > 0))
        '${c.number}': c.learnedNotes,
    },
  };
}

/// Moves the cards to where the daemon says they are.
void applyRun(Project p, List<Map<String, dynamic>> cards) {
  for (final r in cards) {
    final c = p.cards.where((c) => c.number == r['number']).firstOrNull;
    if (c == null) continue;
    final state = r['state'] as String;
    c
      ..state = switch (state) {
        'running' => CardState.running,
        'review' => CardState.review,
        'done' => CardState.done,
        _ => CardState.todo,
      }
      ..sessionId = r['session_id'] as String?
      ..pr = r['pr'] as int?
      ..prUrl = r['pr_url'] as String?
      ..accountId = r['account_id'] as String?
      ..waiting = state == 'todo' ? r['note'] as String? : null
      ..halt = switch (state) {
        'failed' => l10n.coreHaltFailed(
          '${r['note'] ?? l10n.coreUnknownError}',
        ),
        'stopped' => l10n.coreHaltStopped(
          '${r['note'] ?? l10n.coreSessionEnded}',
        ),
        _ => null,
      };
  }
}

/// The loops as the daemon runs them (orc_protocol::CardSpec).
List<Map<String, Object?>> cardSpecs(Project p) => [
  for (final c in p.plan!.proposedCards)
    {
      'number': c.number,
      'title': c.title,
      'branch': c.branch,
      'model': c.model,
      'depends_on': c.dependsOn,
      'prompt': cardPrompt(p, c),
    },
];

/// What the card's session is told (the daemon adds worktree, commit and
/// PR rules).
String cardPrompt(Project p, TaskCard c) {
  final b = StringBuffer()
    ..writeln(l10n.corePromptCard('${c.number}', p.name, c.title, c.type))
    ..writeln();
  if (p.plan!.summary.isNotEmpty) {
    b.writeln('${l10n.corePromptPlan(p.plan!.summary)}\n');
  }
  if (c.description.isNotEmpty) b.writeln('${c.description}\n');
  if (c.criteria.isNotEmpty) {
    b.writeln(l10n.corePromptCriteria);
    for (final k in c.criteria) {
      b.writeln('- $k');
    }
    b.writeln();
  }
  if (c.tasks.isNotEmpty) {
    b.writeln(l10n.corePromptTasks);
    for (final t in c.tasks) {
      final ok = t.needsOk ? l10n.corePromptNeedsOk : '';
      b.writeln(
        '${l10n.corePromptTask('${t.group}', t.title, t.skill, t.model)}$ok',
      );
    }
    b.writeln();
  }
  if (c.notes.isNotEmpty) {
    b.writeln(l10n.corePromptNotes);
    for (final n in c.notes) {
      b.writeln('- ${n.author}: ${n.body}');
    }
  }
  return b.toString().trim();
}

/// First request to the planning session: fill the template.
String draftRequest(String name, String description, List<String> links) => [
  l10n.corePromptDraft(name),
  if (description.isNotEmpty) l10n.corePromptBuild(description),
  if (links.isNotEmpty)
    '${l10n.corePromptSources}\n${links.map((l) => '- $l').join('\n')}',
].join('\n\n');

/// Review request: every comment waiting on the agent, with its thread id
/// and whether its section is approved (then it becomes an amendment).
String reviewRequest(Plan plan) {
  final b = StringBuffer('${l10n.corePromptReview}\n');
  for (final t in plan.threads.where((t) => t.awaitingAgent)) {
    final section = plan.sections.where((s) => s.id == t.anchor).firstOrNull;
    final locked = section?.approved ?? false;
    b.writeln(
      '\n[thread ${t.id}] ${t.anchorLabel}'
      '${locked ? l10n.corePromptLocked : ''}',
    );
    for (final m in t.messages) {
      b.writeln('${m.author}: ${m.body}');
    }
  }
  return b.toString();
}

/// Markdown for a new plan from a template: the plan's own frontmatter and
/// title, then the template's sections with their instructions.
String newPlanMarkdown(
  PlanTemplate template,
  String name,
  String description,
  String repoName,
  List<String> links,
) {
  final body = template.markdown.replaceFirst(
    RegExp(r'^---\n[\s\S]*?\n---\n'),
    '',
  );
  final start = body.indexOf('\n## ');
  final sections = start < 0 ? body : body.substring(start + 1);
  return [
    '---',
    'repo: $repoName',
    if (links.isNotEmpty) ...['sources:', for (final l in links) '  - $l'],
    '---',
    '# $name',
    '',
    if (description.isNotEmpty) ...[description, ''],
    sections,
  ].join('\n');
}

/// A stable text of [v] (map keys sorted), to tell real changes from echoes.
String canonical(Object? v) => jsonEncode(_sorted(v));

Object? _sorted(Object? v) => switch (v) {
  Map() => {
    for (final k in v.keys.map((k) => '$k').toList()..sort()) k: _sorted(v[k]),
  },
  List() => v.map(_sorted).toList(),
  _ => v,
};

DateTime? _time(Object? ms) =>
    ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;

Comment _comment(Object? c) {
  final m = (c as Map).cast<String, dynamic>();
  return Comment(
    m['author'] as String? ?? 'Claude',
    m['body'] as String? ?? '',
    _time(m['at']) ?? DateTime.now(),
  );
}

Map<String, Object?> _commentJson(Comment c) => {
  'author': c.author,
  'body': c.body,
  'at': c.at.millisecondsSinceEpoch,
};
