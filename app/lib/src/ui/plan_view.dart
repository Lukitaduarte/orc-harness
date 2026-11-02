import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../model.dart';
import 'comments.dart';
import 'diagrams.dart';

/// Plan mode, after the create-feature skill: sections from the sources,
/// approved one by one (final), comments that revise open sections or become
/// amendments on approved ones, and "Iniciar execução" once all are approved.
class PlanView extends StatefulWidget {
  const PlanView(this.store, this.project, {super.key});

  final HarnessStore store;
  final Project project;

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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: [
                  _header(),
                  const Gap(16),
                  for (final s in plan.sections) _section(s),
                ],
              ),
              if (!started)
                Positioned(right: 24, bottom: 20, child: _startButton()),
            ],
          ),
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(child: Text(widget.project.name).large().semiBold()),
            const Gap(8),
            OutlineBadge(child: Text('plano v${plan.version}')),
            const Gap(8),
            Text(
              started
                  ? 'em execução desde ${_time(plan.startedAt!)}'
                  : '${plan.approvedCount}/$total seções aprovadas',
            ).xSmall().muted(),
          ],
        ),
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
                Text(
                  'Claude está lendo ${plan.sources.length} fontes e escrevendo as seções…',
                ).small().muted(),
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
    final label = plan.canStart
        ? 'Iniciar execução · ${plan.proposedCards.length} loops'
        : changed > 0
        ? '$changed seção alterada após aprovação'
        : 'Iniciar execução · ${plan.approvedCount}/$total aprovadas';
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
            Row(
              children: [
                Text(s.title).semiBold(),
                if (s.instruction.isNotEmpty) ...[
                  const Gap(6),
                  Tooltip(
                    tooltip: (context) => TooltipContainer(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Text('Instrução do template: ${s.instruction}'),
                      ),
                    ),
                    child: const Icon(LucideIcons.info, size: 14),
                  ),
                ],
                const Gap(8),
                if (s.changedAfterApproval)
                  const DestructiveBadge(child: Text('alterada após aprovação'))
                else if (s.approved)
                  _approvedTag(s),
                const Spacer(),
                if (open > 0)
                  GhostButton(
                    size: ButtonSize.small,
                    onPressed: () => setState(() => _filter = s.id),
                    child: SecondaryBadge(
                      child: Text('$open aberto${open > 1 ? 's' : ''}'),
                    ),
                  ),
                if (!started)
                  GhostButton(
                    size: ButtonSize.small,
                    leading: const Icon(
                      LucideIcons.messageSquarePlus,
                      size: 14,
                    ),
                    onPressed: () => setState(
                      () => _composing = _composing == s.id ? null : s.id,
                    ),
                    child: const Text('Comentar'),
                  ),
                if (!s.approved && !started) ...[
                  const Gap(4),
                  OutlineButton(
                    size: ButtonSize.small,
                    leading: const Icon(LucideIcons.check, size: 12),
                    onPressed: plan.drafting
                        ? null
                        : () => store.approveSection(s),
                    child: const Text('Aprovar'),
                  ),
                ],
              ],
            ),
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
                    ? 'Seção aprovada: o comentário vira emenda do primeiro loop…'
                    : 'Comentar em ${s.title}…',
                onSend: (text) {
                  store.comment(plan, s.id, s.title, text);
                  setState(() {
                    _composing = null;
                    _filter = s.id;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _approvedTag(PlanSection s) => Tooltip(
    tooltip: (context) => TooltipContainer(
      child: Text(
        'Aprovada ${_time(s.approvedAt!)} · digest ${s.approvedDigest}',
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(LucideIcons.circleCheck, size: 14, color: Colors.emerald),
        const Gap(4),
        const Text('aprovada').xSmall().medium(color: Colors.emerald),
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
  Widget _loops(List<TaskCard> loops) => Column(
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
                          ? 'pode começar já'
                          : 'depois do ${l.dependsOn.map((d) => 'loop $d').join(' e ')}',
                    ).xSmall().muted(),
                  ],
                ),
                const Gap(6),
                _table(
                  TableBlock(
                    ['Tarefa', 'Skill', 'Modelo', 'Grupo'],
                    [
                      for (final t in l.tasks)
                        [
                          '${t.id} ${t.title}',
                          t.skill,
                          t.model,
                          'G${t.group}${t.dependsOn.isEmpty ? '' : ' · após ${t.dependsOn.join(', ')}'}${t.needsOk ? ' · seu OK' : ''}',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              const Text('Comentários').semiBold(),
              const Gap(6),
              Text(open == 1 ? '1 aberto' : '$open abertos').xSmall().muted(),
              const Spacer(),
              GhostButton(
                size: ButtonSize.small,
                onPressed: () => setState(() => _showResolved = !_showResolved),
                child: Text(
                  _showResolved ? 'Ocultar resolvidos' : 'Ver resolvidos',
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
                  'Filtrando: ${plan.section(widget.filter!).title}',
                ).xSmall().muted(),
                const Spacer(),
                GhostButton(
                  size: ButtonSize.small,
                  onPressed: widget.onClearFilter,
                  child: const Text('Ver todos'),
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
                  child: const Text(
                    'Nenhum comentário aqui.\nUse "Comentar" em qualquer seção.',
                    textAlign: TextAlign.center,
                  ).small().muted(),
                ),
              for (final t in threads) _thread(t),
              if (plan.amendments.isNotEmpty) ...[
                const Gap(4),
                const Text(
                  'EMENDAS PARA O PRIMEIRO LOOP',
                ).xSmall().semiBold().muted(),
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
                ? const Text(
                    'Claude está revisando os comentários…',
                  ).small().muted()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PrimaryButton(
                        leading: const Icon(LucideIcons.sparkles, size: 14),
                        onPressed: awaiting == 0
                            ? null
                            : () => store.requestPlanReview(plan),
                        child: Text('Pedir revisão ao Claude ($awaiting)'),
                      ),
                      const Gap(6),
                      const Text(
                        'Em seção aberta, Claude ajusta a seção. Em seção aprovada, '
                        'nada muda: o pedido vira emenda do primeiro loop.',
                      ).xSmall().muted(),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _thread(CommentThread t) {
    final store = widget.store;
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
                  const Text('resolvido').xSmall().muted()
                else if (t.awaitingAgent)
                  const Text('aguardando Claude').xSmall().muted(),
                const Spacer(),
                GhostButton(
                  size: ButtonSize.small,
                  onPressed: () => store.setResolved(t, !t.resolved),
                  child: Text(t.resolved ? 'Reabrir' : 'Resolver'),
                ),
              ],
            ),
            const Gap(8),
            CommentList(t.messages, now: store.now),
            if (!t.resolved)
              CommentComposer(
                placeholder: 'Responder…',
                onSend: (text) => store.reply(t, text),
              ),
          ],
        ),
      ),
    );
  }
}
