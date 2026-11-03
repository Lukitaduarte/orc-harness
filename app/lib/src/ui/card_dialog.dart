import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../model.dart';
import 'comments.dart';

/// Card details: description, acceptance criteria, dependencies, git state,
/// and notes from people and agents.
Future<void> showCardDialog(
  BuildContext context,
  HarnessStore store,
  Project project,
  TaskCard card,
) {
  return showOverlay<void>(
    context,
    DialogConfiguration<void>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints.tightFor(width: 640, height: 600),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              child: ListenableBuilder(
                listenable: store,
                builder: (context, _) => _CardDetails(store, project, card),
              ),
            ),
          ),
        );
      },
    ),
  ).future;
}

class _CardDetails extends StatelessWidget {
  const _CardDetails(this.store, this.project, this.card);

  final HarnessStore store;
  final Project project;
  final TaskCard card;

  @override
  Widget build(BuildContext context) {
    final c = card;
    final column = project.columnOf(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#${c.number}').small().muted(),
                        const Gap(6),
                        OutlineBadge(child: Text(c.type)),
                        const Gap(6),
                        SecondaryBadge(child: Text(c.model)),
                        const Gap(6),
                        Text(_columnLabel(column)).xSmall().muted(),
                      ],
                    ),
                    const Gap(6),
                    Text(c.title).large().semiBold(),
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
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (c.description.isNotEmpty) ...[
                Text(c.description).small(),
                const Gap(16),
              ],
              _label('Critérios de aceite'),
              if (c.criteria.isEmpty)
                const Text('Nenhum critério definido.').small().muted()
              else
                for (final item in c.criteria)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          c.state == CardState.done
                              ? LucideIcons.circleCheck
                              : LucideIcons.circle,
                          size: 14,
                        ),
                        const Gap(8),
                        Expanded(child: Text(item).small()),
                      ],
                    ),
                  ),
              const Gap(16),
              if (c.tasks.isNotEmpty) ...[
                _label('Tarefas · subagentes por grupo'),
                for (final g in {for (final t in c.tasks) t.group}) ...[
                  Text(
                    c.tasks.where((t) => t.group == g).length > 1
                        ? 'Grupo $g · em paralelo'
                        : 'Grupo $g',
                  ).xSmall().semiBold().muted(),
                  const Gap(4),
                  for (final t in c.tasks.where((t) => t.group == g))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text(t.id).xSmall().muted(),
                          ),
                          Expanded(child: Text(t.title).small()),
                          Text(t.skill).mono().xSmall().muted(),
                          if (t.needsOk) ...[
                            const Gap(8),
                            const PrimaryBadge(child: Text('seu OK')),
                          ],
                          const Gap(8),
                          SecondaryBadge(child: Text(t.model)),
                        ],
                      ),
                    ),
                  const Gap(6),
                ],
                const Gap(10),
              ],
              if (c.delivered.isNotEmpty ||
                  c.problems.isNotEmpty ||
                  c.gates.isNotEmpty) ...[
                _label('Resultado do loop'),
                for (final d in c.delivered) Text('✓  $d').small(),
                for (final p in c.problems) Text('!  $p').small().muted(),
                if (c.gates.isNotEmpty) ...[
                  const Gap(6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final MapEntry(:key, :value) in c.gates.entries)
                        OutlineBadge(child: Text('$key: $value')),
                    ],
                  ),
                ],
                const Gap(16),
              ],
              _label('Dependências'),
              if (c.dependsOn.isEmpty)
                const Text(
                  'Nenhuma: pode rodar em paralelo com outros cards prontos.',
                ).small().muted()
              else
                for (final d in c.dependsOn)
                  _dependency(context, project.card(d)),
              const Gap(16),
              _label('Git'),
              _row('Branch', c.branch, mono: true),
              if (c.sessionId != null)
                _row('Sessão', store.session(c.sessionId!).name),
              if (c.pr != null) _row('PR', '#${c.pr}'),
              const Gap(16),
              _label('Comentários e observações'),
              if (c.notes.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('Nenhum comentário ainda.'),
                ).small().muted()
              else
                CommentList(c.notes, now: store.now),
              CommentComposer(
                placeholder: 'Adicionar observação…',
                onSend: (text) => store.addCardNote(c, text),
              ),
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (column == KanbanColumn.ready && c.halt != null)
                PrimaryButton(
                  leading: const Icon(LucideIcons.rotateCcw, size: 14),
                  onPressed: () {
                    store.retryCard(project, c);
                    closeOverlay(context);
                  },
                  child: const Text('Tentar de novo'),
                ),
              if (column == KanbanColumn.ready && !store.isLiveProject(project))
                PrimaryButton(
                  leading: const Icon(LucideIcons.play, size: 14),
                  onPressed: store.canRun(project)
                      ? () => store.runCard(project, c)
                      : null,
                  child: const Text('Executar'),
                ),
              if (c.sessionId != null &&
                  column == KanbanColumn.running &&
                  store.sessions.any((s) => s.id == c.sessionId))
                OutlineButton(
                  onPressed: () {
                    closeOverlay(context);
                    store.showSession(c.sessionId!);
                  },
                  child: const Text('Abrir sessão'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text.toUpperCase()).xSmall().semiBold().muted(),
  );

  Widget _row(String label, String value, {bool mono = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(width: 72, child: Text(label).small().muted()),
        Expanded(
          child: mono ? Text(value).mono().xSmall() : Text(value).small(),
        ),
      ],
    ),
  );

  Widget _dependency(BuildContext context, TaskCard d) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Icon(
          d.state == CardState.done
              ? LucideIcons.circleCheck
              : LucideIcons.clock,
          size: 14,
        ),
        const Gap(8),
        Text('#${d.number}').small().muted(),
        const Gap(6),
        Expanded(child: Text(d.title).small()),
        Text(d.state == CardState.done ? 'feito' : 'pendente').xSmall().muted(),
      ],
    ),
  );

  static String _columnLabel(KanbanColumn c) => switch (c) {
    KanbanColumn.blocked => 'bloqueado',
    KanbanColumn.ready => 'pronto',
    KanbanColumn.running => 'em execução',
    KanbanColumn.review => 'em review',
    KanbanColumn.done => 'feito',
  };
}
