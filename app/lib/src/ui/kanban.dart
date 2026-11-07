import 'package:url_launcher/url_launcher.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../model.dart';
import 'card_dialog.dart';
import 'learn_dialog.dart';

/// Project board. Columns come from the dependency graph: a card with every
/// dependency done is ready and can run in parallel with other ready cards.
class KanbanView extends StatelessWidget {
  const KanbanView(this.store, this.project, {super.key});

  final HarnessStore store;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final ready = store.readyCards(p);
    final running = store.runningCount(p);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name).large().semiBold(),
                    Text(
                      l10n.plansBoardSummary(
                        p.repo,
                        p.doneCount,
                        p.cards.length,
                        running,
                        HarnessStore.maxRunningCards,
                      ),
                    ).xSmall().muted(),
                  ],
                ),
              ),
              OutlineButton(
                leading: const Icon(LucideIcons.graduationCap, size: 14),
                onPressed: () {
                  store.learn(p);
                  showLearningsDialog(context, store, p);
                },
                child: Text(
                  store.unlearnedNotes(p) == 0
                      ? 'Learn'
                      : 'Learn (${store.unlearnedNotes(p)})',
                ),
              ),
              const Gap(8),
              if (ready.isNotEmpty)
                PrimaryButton(
                  leading: const Icon(LucideIcons.play, size: 14),
                  onPressed: store.canRun(p) ? () => store.runReady(p) : null,
                  child: Text(l10n.plansRunReady(ready.length)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.plansBoardHint(store.freestAccount.email),
          ).xSmall().muted(),
        ),
        const Gap(12),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final col in KanbanColumn.values)
                _Column(
                  store,
                  p,
                  col,
                  p.cards.where((c) => p.columnOf(c) == col).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Column extends StatelessWidget {
  const _Column(this.store, this.project, this.column, this.cards);

  final HarnessStore store;
  final Project project;
  final KanbanColumn column;
  final List<TaskCard> cards;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = switch (column) {
      KanbanColumn.blocked => l10n.plansColumnBlocked,
      KanbanColumn.ready => l10n.plansColumnReady,
      KanbanColumn.running => l10n.plansColumnRunning,
      KanbanColumn.review => l10n.plansColumnReview,
      KanbanColumn.done => l10n.plansColumnDone,
    };
    return Container(
      width: 272,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Row(
              children: [
                Text(title).small().semiBold(),
                const Gap(6),
                Text('${cards.length}').xSmall().muted(),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final c in cards) _CardTile(store, project, c, column),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile(this.store, this.project, this.card, this.column);

  final HarnessStore store;
  final Project project;
  final TaskCard card;
  final KanbanColumn column;

  @override
  Widget build(BuildContext context) {
    final c = card;
    final pending = c.dependsOn
        .where((d) => project.card(d).state != CardState.done)
        .toList();
    final l10n = context.l10n;
    final deps = switch (column) {
      KanbanColumn.blocked => l10n.plansWaitingFor(_refs(pending)),
      _ when c.dependsOn.isEmpty => l10n.plansNoDependencies,
      _ => l10n.plansDependsOn(_refs(c.dependsOn)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => showCardDialog(context, store, project, c),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: OutlinedContainer(
            backgroundColor: Theme.of(context).colorScheme.card,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('#${c.number}').xSmall().muted(),
                    const Gap(6),
                    OutlineBadge(child: Text(c.type)),
                    const Spacer(),
                    SecondaryBadge(child: Text(c.model)),
                  ],
                ),
                const Gap(8),
                Text(c.title).small().semiBold(),
                const Gap(4),
                Text(deps).xSmall().muted(),
                if (column != KanbanColumn.blocked &&
                    column != KanbanColumn.ready) ...[
                  const Gap(6),
                  Row(
                    children: [
                      const Icon(LucideIcons.gitBranch, size: 12),
                      const Gap(4),
                      Expanded(
                        child: Text(
                          c.branch,
                          overflow: TextOverflow.ellipsis,
                        ).mono().xSmall().muted(),
                      ),
                    ],
                  ),
                ],
                ..._actions(l10n),
                if (c.notes.isNotEmpty) ...[
                  const Gap(8),
                  Row(
                    children: [
                      const Icon(LucideIcons.messageSquare, size: 12),
                      const Gap(4),
                      Text('${c.notes.length}').xSmall().muted(),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(AppLocalizations l10n) {
    final c = card;
    if (store.isLiveProject(project)) return _liveActions(c, l10n);
    final row = switch (column) {
      KanbanColumn.blocked => null,
      KanbanColumn.ready => [
        PrimaryButton(
          size: ButtonSize.small,
          leading: const Icon(LucideIcons.play, size: 12),
          onPressed: store.canRun(project)
              ? () => store.runCard(project, c)
              : null,
          child: Text(l10n.plansRun),
        ),
      ],
      KanbanColumn.running => [
        OutlineButton(
          size: ButtonSize.small,
          onPressed: () => store.showSession(c.sessionId!),
          child: Text(l10n.plansOpenSession),
        ),
        const Gap(4),
        _simulate(l10n.plansSimulatePr, () => store.simulatePr(c)),
      ],
      KanbanColumn.review => [
        OutlineButton(
          size: ButtonSize.small,
          leading: const Icon(LucideIcons.gitPullRequest, size: 12),
          onPressed: () {},
          child: Text('PR #${c.pr}'),
        ),
        const Gap(4),
        _simulate(l10n.plansSimulateMerge, () => store.simulateMerge(c)),
      ],
      KanbanColumn.done => [
        const Icon(LucideIcons.check, size: 12),
        const Gap(4),
        Text(l10n.plansPrMerged(c.pr!)).xSmall().muted(),
      ],
    };
    return row == null ? const [] : [const Gap(10), Row(children: row)];
  }

  /// Live cards: the daemon starts them and GitHub moves them.
  List<Widget> _liveActions(TaskCard c, AppLocalizations l10n) {
    final hasSession = store.sessions.any((s) => s.id == c.sessionId);
    final pr = c.prUrl == null
        ? null
        : OutlineButton(
            size: ButtonSize.small,
            leading: const Icon(LucideIcons.gitPullRequest, size: 12),
            onPressed: () => launchUrl(Uri.parse(c.prUrl!)),
            child: Text('PR #${c.pr}'),
          );
    final row = switch (column) {
      KanbanColumn.blocked => null,
      KanbanColumn.ready when c.halt != null => [
        Expanded(
          child: Text(
            c.halt!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ).xSmall().muted(),
        ),
        const Gap(4),
        OutlineButton(
          size: ButtonSize.small,
          leading: const Icon(LucideIcons.rotateCcw, size: 12),
          onPressed: () => store.retryCard(project, c),
          child: Text(l10n.plansRetry),
        ),
      ],
      KanbanColumn.ready => [
        Expanded(
          child: Text(
            c.waiting ?? l10n.plansQueued,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ).xSmall().muted(),
        ),
      ],
      KanbanColumn.running || KanbanColumn.review => [
        if (c.accountId != null) ...[
          OutlineBadge(child: Text(c.accountId!)),
          const Gap(4),
        ],
        if (hasSession)
          OutlineButton(
            size: ButtonSize.small,
            onPressed: () => store.showSession(c.sessionId!),
            child: Text(l10n.plansOpenSession),
          ),
        if (hasSession && pr != null) const Gap(4),
        ?pr,
      ],
      KanbanColumn.done => [
        const Icon(LucideIcons.check, size: 12),
        const Gap(4),
        if (pr != null) pr else Text(l10n.plansMerged).xSmall().muted(),
      ],
    };
    return row == null ? const [] : [const Gap(10), Row(children: row)];
  }

  /// Stand-in for events the daemon will report (PR opened, PR merged).
  Widget _simulate(String label, VoidCallback onPressed) => Tooltip(
    tooltip: (context) =>
        TooltipContainer(child: Text(context.l10n.plansPhaseZeroSimulation)),
    child: GhostButton(
      size: ButtonSize.small,
      onPressed: onPressed,
      child: Text(label).muted(),
    ),
  );

  static String _refs(List<int> ns) => ns.map((n) => '#$n').join(', ');
}
