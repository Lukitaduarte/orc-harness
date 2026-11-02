import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
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
                      '${p.repo} · ${p.doneCount}/${p.cards.length} feitos · '
                      '$running/${HarnessStore.maxRunningCards} em execução',
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
                  child: Text('Executar prontos (${ready.length})'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Cada card roda na própria worktree e sessão, na conta com mais '
            'folga (${store.freestAccount.email}).',
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
    final title = switch (column) {
      KanbanColumn.blocked => 'Bloqueados',
      KanbanColumn.ready => 'Prontos',
      KanbanColumn.running => 'Em execução',
      KanbanColumn.review => 'Em review',
      KanbanColumn.done => 'Feitos',
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
    final deps = switch (column) {
      KanbanColumn.blocked => 'aguardando ${_refs(pending)}',
      _ when c.dependsOn.isEmpty => 'sem dependências',
      _ => 'depende de ${_refs(c.dependsOn)}',
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
                ..._actions(),
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

  List<Widget> _actions() {
    final c = card;
    final row = switch (column) {
      KanbanColumn.blocked => null,
      KanbanColumn.ready => [
        PrimaryButton(
          size: ButtonSize.small,
          leading: const Icon(LucideIcons.play, size: 12),
          onPressed: store.canRun(project)
              ? () => store.runCard(project, c)
              : null,
          child: const Text('Executar'),
        ),
      ],
      KanbanColumn.running => [
        OutlineButton(
          size: ButtonSize.small,
          onPressed: () => store.showSession(c.sessionId!),
          child: const Text('Abrir sessão'),
        ),
        const Gap(4),
        _simulate('Simular PR', () => store.simulatePr(c)),
      ],
      KanbanColumn.review => [
        OutlineButton(
          size: ButtonSize.small,
          leading: const Icon(LucideIcons.gitPullRequest, size: 12),
          onPressed: () {},
          child: Text('PR #${c.pr}'),
        ),
        const Gap(4),
        _simulate('Simular merge', () => store.simulateMerge(c)),
      ],
      KanbanColumn.done => [
        const Icon(LucideIcons.check, size: 12),
        const Gap(4),
        Text('PR #${c.pr} mergeado').xSmall().muted(),
      ],
    };
    return row == null ? const [] : [const Gap(10), Row(children: row)];
  }

  /// Stand-in for events the daemon will report (PR opened, PR merged).
  Widget _simulate(String label, VoidCallback onPressed) => Tooltip(
    tooltip: (context) =>
        const TooltipContainer(child: Text('Simulação da fase 0')),
    child: GhostButton(
      size: ButtonSize.small,
      onPressed: onPressed,
      child: Text(label).muted(),
    ),
  );

  static String _refs(List<int> ns) => ns.map((n) => '#$n').join(', ');
}
