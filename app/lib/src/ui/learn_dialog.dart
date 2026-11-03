import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../model.dart';

/// Learn: comments on the cards turned into proposed skill changes. Nothing
/// is applied without your OK.
Future<void> showLearningsDialog(
  BuildContext context,
  HarnessStore store,
  Project project,
) {
  return showOverlay<void>(
    context,
    DialogConfiguration<void>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints.tightFor(width: 600, height: 480),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              child: ListenableBuilder(
                listenable: store,
                builder: (context, _) => _Learnings(store, project),
              ),
            ),
          ),
        );
      },
    ),
  ).future;
}

class _Learnings extends StatelessWidget {
  const _Learnings(this.store, this.project);

  final HarnessStore store;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final items = store.learningsOf(project).reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Learn').large().semiBold(),
                    const Text(
                      'Cada comentário nos cards vira uma mudança na skill que tem a lacuna. '
                      'Você aprova antes de aplicar.',
                    ).xSmall().muted(),
                  ],
                ),
              ),
              GhostButton(
                density: ButtonDensity.icon,
                onPressed: () => closeOverlay(context),
                child: const Icon(LucideIcons.x, size: 16),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    project.live
                        ? 'O Claude está lendo os comentários e as skills dos cards.\n'
                              'As propostas aparecem aqui; nada muda sem o seu OK.'
                        : 'Nenhum comentário novo nos cards.\n'
                              'Comente no dialog de um card e rode o Learn de novo.',
                    textAlign: TextAlign.center,
                  ).small().muted(),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [for (final l in items) _item(context, l)],
                ),
        ),
      ],
    );
  }

  Widget _item(BuildContext context, Learning l) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: OutlinedContainer(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              OutlineBadge(child: Text(l.skill)),
              const Gap(6),
              Text(l.file).mono().xSmall().muted(),
              const Spacer(),
              Text(l.source).xSmall().muted(),
            ],
          ),
          const Gap(8),
          Text(l.summary).small(),
          if (l.replacement.isNotEmpty) ...[
            const Gap(8),
            if (l.old.isNotEmpty)
              _passage(
                context,
                '−',
                l.old,
                Theme.of(context).colorScheme.destructive,
              ),
            _passage(context, '+', l.replacement, Colors.emerald),
          ],
          if (l.error != null) ...[
            const Gap(6),
            Text(
              'Não aplicou: ${l.error}',
            ).xSmall().medium(color: Theme.of(context).colorScheme.destructive),
          ],
          const Gap(10),
          switch (l.accepted) {
            null => Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: () => store.decideLearning(project, l, false),
                  child: const Text('Descartar'),
                ),
                const Gap(8),
                PrimaryButton(
                  size: ButtonSize.small,
                  onPressed: () => store.decideLearning(project, l, true),
                  child: const Text('Aplicar na skill'),
                ),
              ],
            ),
            true => const Text(
              'Aplicado na skill',
            ).xSmall().medium(color: Colors.emerald),
            false => const Text('Descartado').xSmall().muted(),
          },
        ],
      ),
    ),
  );

  /// One side of the edit, marked − (removed) or + (added).
  Widget _passage(
    BuildContext context,
    String mark,
    String text,
    Color color,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: color, width: 3)),
      color: Theme.of(context).colorScheme.muted,
    ),
    child: Text('$mark $text').mono().xSmall(),
  );
}
