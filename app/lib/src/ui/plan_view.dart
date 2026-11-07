import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../model.dart';
import 'comments.dart';
import 'diagrams.dart';

/// Plan mode, after the create-feature skill: sections from the sources,
/// approved one by one (final), comments that revise open sections or become
/// amendments on approved ones, and "Iniciar execução" once all are approved.
class PlanView extends StatefulWidget {
  const PlanView(this.store, this.project, {super.key, this.compact = false});

  final HarnessStore store;
  final Project project;

  /// Phone: no side panel; each section shows its own comments.
  final bool compact;

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
  /// Section currently showing the new-comment field.
  String? _composing;

  /// Section the review panel is filtered to; null shows every thread.
  String? _filter;

  HarnessStore get store => widget.store;
  Plan get plan => widget.project.plan!;

  /// Read-only once execution started.
  bool get started => plan.startedAt != null;

  @override
  Widget build(BuildContext context) {
    final sections = Stack(
      children: [
        ListView(
          padding: EdgeInsets.fromLTRB(
            widget.compact ? 10 : 16,
            16,
            widget.compact ? 10 : 16,
            88,
          ),
          children: [
            _header(),
            const Gap(16),
            for (final s in plan.sections) _section(s),
          ],
        ),
        if (!started) Positioned(right: 24, bottom: 20, child: _startButton()),
      ],
    );
    if (widget.compact) return sections;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: sections),
        const VerticalDivider(),
        SizedBox(
          width: 340,
          child: _ReviewPanel(
            store: store,
            plan: plan,
            filter: _filter,
            onClearFilter: () => setState(() => _filter = null),
          ),
        ),
      ],
    );
  }

  Widget _header() {
    final total = plan.sections.length;
    final review = plan.threads.any((t) => t.awaitingAgent);
    final t = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line([
          Flexible(child: Text(widget.project.name).large().semiBold()),
          const Gap(8),
          OutlineBadge(child: Text(t.plansVersion(plan.version))),
          const Gap(8),
          Text(
            started
                ? t.plansRunningSince(_time(plan.startedAt!))
                : t.plansApprovedCount(plan.approvedCount, total),
          ).xSmall().muted(),
          const Spacer(),
          if (plan.plannerSession case final id?
              when store.sessions.any((s) => s.id == id))
            GhostButton(
              size: ButtonSize.small,
              leading: const Icon(LucideIcons.terminal, size: 12),
              onPressed: () => store.showSession(id),
              child: Text(t.plansPlanningSession),
            ),
          // On the phone the review panel is not there: ask from here.
          if (widget.compact && review && !started)
            OutlineButton(
              size: ButtonSize.small,
              onPressed: plan.reviewing
                  ? null
                  : () => store.requestPlanReview(plan),
              child: Text(
                plan.reviewing
                    ? t.plansClaudeReviewing
                    : t.plansAskClaudeReview,
              ),
            ),
        ]),
        const Gap(6),
        Text(plan.summary).small(),
        const Gap(8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in plan.sources)
              OutlineBadge(child: Text('${s.kind} · ${_short(s.url)}')),
          ],
        ),
        if (plan.drafting) ...[
          const Gap(12),
          OutlinedContainer(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(LucideIcons.loader, size: 14),
                const Gap(8),
                Text(t.plansDrafting(plan.sources.length)).small().muted(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _startButton() {
    final total = plan.sections.length;
    final changed = plan.sections.where((s) => s.changedAfterApproval).length;
    final t = context.l10n;
    final label = plan.canStart
        ? t.plansStartLoops(plan.proposedCards.length)
        : changed > 0
        ? t.plansChangedAfterApprovalCount(changed)
        : t.plansStartApproved(plan.approvedCount, total);
    return PrimaryButton(
      leading: const Icon(LucideIcons.play, size: 14),
      onPressed: plan.canStart
          ? () => store.startExecution(widget.project)
          : null,
      child: Text(label),
    );
  }

  Widget _section(PlanSection s) {
    final open = plan.threadsOn(s.id).where((t) => !t.resolved).length;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedContainer(
        padding: const EdgeInsets.all(14),
        borderColor: s.changedAfterApproval
            ? Theme.of(context).colorScheme.destructive
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _line([
              Text(s.title).semiBold(),
              if (s.instruction.isNotEmpty) ...[
                const Gap(6),
                Tooltip(
                  tooltip: (context) => TooltipContainer(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Text(l10n.plansTemplateInstruction(s.instruction)),
                    ),
                  ),
                  child: const Icon(LucideIcons.info, size: 14),
                ),
              ],
              const Gap(8),
              if (s.changedAfterApproval)
                DestructiveBadge(child: Text(l10n.plansChangedAfterApproval))
              else if (s.approved)
                _approvedTag(s),
              const Spacer(),
              if (open > 0)
                GhostButton(
                  size: ButtonSize.small,
                  onPressed: () => setState(() => _filter = s.id),
                  child: SecondaryBadge(child: Text(l10n.plansOpenCount(open))),
                ),
              if (!started)
                GhostButton(
                  size: ButtonSize.small,
                  leading: const Icon(LucideIcons.messageSquarePlus, size: 14),
                  onPressed: () => setState(
                    () => _composing = _composing == s.id ? null : s.id,
                  ),
                  child: Text(l10n.plansComment),
                ),
              if (!s.approved && !started) ...[
                const Gap(4),
                OutlineButton(
                  size: ButtonSize.small,
                  leading: const Icon(LucideIcons.check, size: 12),
                  onPressed: plan.drafting
                      ? null
                      : () => store.approveSection(s),
                  child: Text(l10n.plansApprove),
                ),
              ],
            ]),
            const Gap(10),
            for (final b in s.blocks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _block(b),
              ),
            if (_composing == s.id)
              CommentComposer(
                autofocus: true,
                placeholder: s.approved
                    ? l10n.plansApprovedSectionPlaceholder
                    : l10n.plansCommentOn(s.title),
                onSend: (text) {
                  store.comment(plan, s.id, s.title, text);
                  setState(() {
                    _composing = null;
                    _filter = s.id;
                  });
                },
              ),
            if (widget.compact)
              for (final t in plan.threadsOn(s.id).where((t) => !t.resolved))
                threadCard(store, t),
          ],
        ),
      ),
    );
  }

  /// A row of header items; on the phone they wrap instead (no Spacer).
  Widget _line(List<Widget> children) => widget.compact
      ? Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final c in children)
              if (c is! Spacer && c is! Gap) c is Flexible ? c.child : c,
          ],
        )
      : Row(children: children);

  Widget _approvedTag(PlanSection s) => Tooltip(
    tooltip: (context) => TooltipContainer(
      child: Text(
        context.l10n.plansApprovedAt(_time(s.approvedAt!), s.approvedDigest!),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.circleCheck, size: 14, color: Colors.emerald),
        const Gap(4),
        Text(context.l10n.plansApproved).xSmall().medium(color: Colors.emerald),
      ],
    ),
  );

  Widget _block(PlanBlock b) => switch (b) {
    TextBlock() => Text(b.text).small(),
    BulletsBlock() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in b.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('•  $item').small(),
          ),
      ],
    ),
    TableBlock() => _table(b),
    CodeBlock() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (b.caption.isNotEmpty) ...[
          Text(b.caption).mono().xSmall().muted(),
          const Gap(4),
        ],
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.muted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(b.code).mono().xSmall(),
        ),
      ],
    ),
    FlowchartBlock() => FlowchartView(b),
    SequenceBlock() => SequenceView(b),
    LoopsBlock() => _loops(b.loops),
  };

  Widget _table(TableBlock t) {
    Widget row(List<String> cells, {bool head = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in cells)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: head ? Text(c).xSmall().semiBold().muted() : _cell(c),
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(t.headers, head: true),
        const Divider(),
        for (final r in t.rows) row(r),
      ],
    );
  }

  /// Severity, origin and model values read as tags, like the skill's page.
  Widget _cell(String c) => switch (c) {
    'bloqueia' => Align(
      alignment: Alignment.centerLeft,
      child: DestructiveBadge(child: Text(c)),
    ),
    'opus' || 'sonnet' || 'haiku' => Align(
      alignment: Alignment.centerLeft,
      child: SecondaryBadge(child: Text(c)),
    ),
    'configurado' => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.circleCheck, size: 13, color: Colors.emerald),
        const Gap(4),
        Text(c).small().medium(color: Colors.emerald),
      ],
    ),
    'seu OK' => Align(
      alignment: Alignment.centerLeft,
      child: PrimaryBadge(child: Text(c)),
    ),
    'médio' || 'baixo' || 'pendente' => Align(
      alignment: Alignment.centerLeft,
      child: OutlineBadge(child: Text(c)),
    ),
    _ => Text(c).small(),
  };

  /// Each loop is one PR; its tasks run in parallel groups.
  Widget _loops(List<TaskCard> loops) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final l in loops)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedContainer(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('Loop ${l.number}').xSmall().muted(),
                      const Gap(6),
                      Expanded(child: Text(l.title).small().semiBold()),
                      Text(
                        l.dependsOn.isEmpty
                            ? l10n.plansCanStartNow
                            : l10n.plansAfterLoops(
                                l.dependsOn
                                    .map(l10n.plansLoopRef)
                                    .join(l10n.plansListAnd),
                              ),
                      ).xSmall().muted(),
                    ],
                  ),
                  const Gap(6),
                  _table(
                    TableBlock(
                      [
                        l10n.plansTableTask,
                        'Skill',
                        l10n.plansTableModel,
                        l10n.plansTableGroup,
                      ],
                      [
                        for (final t in l.tasks)
                          [
                            '${t.id} ${t.title}',
                            t.skill,
                            t.model,
                            'G${t.group}${t.dependsOn.isEmpty ? '' : ' · ${l10n.plansTaskAfter(t.dependsOn.join(', '))}'}${t.needsOk ? ' · ${l10n.plansYourOk}' : ''}',
                          ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _short(String url) {
    final u = url.replaceFirst(RegExp(r'^https?://(www\.)?'), '');
    return u.length > 40 ? '${u.substring(0, 40)}…' : u;
  }
}

class _ReviewPanel extends StatefulWidget {
  const _ReviewPanel({
    required this.store,
    required this.plan,
    required this.filter,
    required this.onClearFilter,
  });

  final HarnessStore store;
  final Plan plan;
  final String? filter;
  final VoidCallback onClearFilter;

  @override
  State<_ReviewPanel> createState() => _ReviewPanelState();
}

class _ReviewPanelState extends State<_ReviewPanel> {
  bool _showResolved = false;

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final store = widget.store;
    final threads = plan.threads
        .where((t) => widget.filter == null || t.anchor == widget.filter)
        .where((t) => _showResolved || !t.resolved)
        .toList();
    final awaiting = plan.threads.where((t) => t.awaitingAgent).length;
    final open = plan.openThreads;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Text(l10n.plansComments).semiBold(),
              const Gap(6),
              Text(l10n.plansOpenCount(open)).xSmall().muted(),
              const Spacer(),
              GhostButton(
                size: ButtonSize.small,
                onPressed: () => setState(() => _showResolved = !_showResolved),
                child: Text(
                  _showResolved
                      ? l10n.plansHideResolved
                      : l10n.plansShowResolved,
                ),
              ),
            ],
          ),
        ),
        if (widget.filter != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  l10n.plansFiltering(plan.section(widget.filter!).title),
                ).xSmall().muted(),
                const Spacer(),
                GhostButton(
                  size: ButtonSize.small,
                  onPressed: widget.onClearFilter,
                  child: Text(l10n.plansShowAll),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (threads.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    l10n.plansNoCommentsHere,
                    textAlign: TextAlign.center,
                  ).small().muted(),
                ),
              for (final t in threads) _thread(t),
              if (plan.amendments.isNotEmpty) ...[
                const Gap(4),
                Text(l10n.plansAmendmentsHeader).xSmall().semiBold().muted(),
                const Gap(6),
                for (final a in plan.amendments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('•  $a').xSmall(),
                  ),
              ],
            ],
          ),
        ),
        if (plan.startedAt == null) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: plan.reviewing
                ? Text(l10n.plansClaudeReviewingComments).small().muted()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryButton(
                        leading: const Icon(LucideIcons.sparkles, size: 14),
                        onPressed: awaiting == 0
                            ? null
                            : () => store.requestPlanReview(plan),
                        child: Text(l10n.plansAskClaudeReviewCount(awaiting)),
                      ),
                      const Gap(6),
                      Text(l10n.plansReviewHint).xSmall().muted(),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _thread(CommentThread t) => threadCard(widget.store, t);
}

/// A comment thread with replies and resolve (review panel and phone).
Widget threadCard(HarnessStore store, CommentThread t) {
  return Builder(
    builder: (context) {
      final l10n = context.l10n;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedContainer(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OutlineBadge(child: Text(t.anchorLabel)),
                  const Gap(6),
                  if (t.resolved)
                    Text(l10n.plansResolved).xSmall().muted()
                  else if (t.awaitingAgent)
                    Text(l10n.plansAwaitingClaude).xSmall().muted(),
                  const Spacer(),
                  GhostButton(
                    size: ButtonSize.small,
                    onPressed: () => store.setResolved(t, !t.resolved),
                    child: Text(
                      t.resolved ? l10n.plansReopen : l10n.plansResolve,
                    ),
                  ),
                ],
              ),
              const Gap(8),
              CommentList(t.messages, now: store.now),
              if (!t.resolved)
                CommentComposer(
                  placeholder: l10n.plansReply,
                  onSend: (text) => store.reply(t, text),
                ),
            ],
          ),
        ),
      );
    },
  );
}
