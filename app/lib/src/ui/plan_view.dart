import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../model.dart';
import 'comments.dart';

/// Plan mode: the plan as reviewable sections, comments anchored to each
/// section or proposed card, and approval that turns cards into the board.
class PlanView extends StatefulWidget {
  const PlanView(this.store, this.project, {super.key});

  final HarnessStore store;
  final Project project;

  @override
  State<PlanView> createState() => _PlanViewState();
}

class _PlanViewState extends State<PlanView> {
  /// Section or card currently showing the new-comment field.
  String? _composing;

  /// Anchor the review panel is filtered to; null shows every thread.
  String? _filter;

  HarnessStore get store => widget.store;
  Plan get plan => widget.project.plan!;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(),
              const Gap(16),
              _section('resumo', 'Resumo', Text(plan.summary).small()),
              _section('arquitetura', 'Arquitetura', _architecture()),
              _section('pastas', 'Estrutura de pastas', _folders()),
              _section('stack', 'Stack', _stack()),
              _section('cards', 'Cards propostos', _cards()),
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
    final open = plan.openThreads;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(widget.project.name).large().semiBold(),
                  const Gap(8),
                  OutlineBadge(child: Text('plano v${plan.version}')),
                ],
              ),
              Text(
                open == 0
                    ? '${widget.project.repo} · sem comentários abertos, pronto para aprovar'
                    : open == 1
                    ? '${widget.project.repo} · resolva o comentário aberto para aprovar'
                    : '${widget.project.repo} · resolva os $open comentários abertos para aprovar',
              ).xSmall().muted(),
            ],
          ),
        ),
        PrimaryButton(
          leading: const Icon(LucideIcons.check, size: 14),
          onPressed: open == 0 ? () => store.approvePlan(widget.project) : null,
          child: Text('Aprovar e criar ${plan.proposedCards.length} cards'),
        ),
      ],
    );
  }

  Widget _section(String anchor, String title, Widget body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedContainer(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(title).semiBold(),
                const Spacer(),
                _commentButton(anchor, title),
              ],
            ),
            const Gap(10),
            body,
            if (_composing == anchor) ...[
              const Gap(10),
              CommentComposer(
                autofocus: true,
                placeholder: 'Comentar em $title…',
                onSend: (text) {
                  store.comment(plan, anchor, title, text);
                  setState(() {
                    _composing = null;
                    _filter = anchor;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Opens the comment field; the count opens the anchor's threads.
  Widget _commentButton(String anchor, String label) {
    final open = plan.threadsOn(anchor).where((t) => !t.resolved).length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (open > 0)
          GhostButton(
            size: ButtonSize.small,
            onPressed: () => setState(() => _filter = anchor),
            child: SecondaryBadge(
              child: Text('$open aberto${open > 1 ? 's' : ''}'),
            ),
          ),
        GhostButton(
          size: ButtonSize.small,
          leading: const Icon(LucideIcons.messageSquarePlus, size: 14),
          onPressed: () =>
              setState(() => _composing = _composing == anchor ? null : anchor),
          child: const Text('Comentar'),
        ),
      ],
    );
  }

  Widget _architecture() {
    final boxes = plan.architecture;
    // Boxes share the width so the whole flow is visible at once.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < boxes.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(LucideIcons.arrowRight, size: 16),
              ),
            Expanded(
              child: OutlinedContainer(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(boxes[i].name).small().semiBold(),
                    Text(boxes[i].detail).xSmall().muted(),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _folders() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.muted.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(plan.folders).mono().xSmall(),
  );

  Widget _stack() => Column(
    children: [
      for (final (layer, choice) in plan.stack)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 120, child: Text(layer).small().muted()),
              Expanded(child: Text(choice).small()),
            ],
          ),
        ),
    ],
  );

  /// Cards grouped in waves: every card of a wave can run in parallel.
  Widget _cards() {
    final cards = plan.proposedCards;
    final wave = <int, int>{};
    int waveOf(TaskCard c) => wave[c.number] ??= c.dependsOn.isEmpty
        ? 1
        : 1 +
              c.dependsOn
                  .map((d) => waveOf(cards.firstWhere((x) => x.number == d)))
                  .reduce((a, b) => a > b ? a : b);
    final waves = <int, List<TaskCard>>{};
    for (final c in cards) {
      waves.putIfAbsent(waveOf(c), () => []).add(c);
    }
    final keys = waves.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final w in keys) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              waves[w]!.length > 1
                  ? 'Onda $w · ${waves[w]!.length} cards em paralelo'
                  : 'Onda $w',
            ).xSmall().semiBold().muted(),
          ),
          for (final c in waves[w]!) _proposedCard(c),
        ],
      ],
    );
  }

  Widget _proposedCard(TaskCard c) {
    final anchor = 'card-${c.number}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedContainer(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('#${c.number}').xSmall().muted(),
                const Gap(6),
                OutlineBadge(child: Text(c.type)),
                const Gap(8),
                Expanded(child: Text(c.title).small().semiBold()),
                SecondaryBadge(child: Text(c.model)),
                const Gap(4),
                _commentButton(anchor, 'Card #${c.number}'),
              ],
            ),
            if (c.description.isNotEmpty || c.dependsOn.isNotEmpty) ...[
              const Gap(4),
              Text(
                [
                  if (c.description.isNotEmpty) c.description,
                  if (c.dependsOn.isNotEmpty)
                    'depende de ${c.dependsOn.map((d) => '#$d').join(', ')}',
                ].join(' · '),
              ).xSmall().muted(),
            ],
            if (_composing == anchor) ...[
              const Gap(8),
              CommentComposer(
                autofocus: true,
                placeholder: 'Comentar no card #${c.number}…',
                onSend: (text) {
                  store.comment(plan, anchor, 'Card #${c.number}', text);
                  setState(() {
                    _composing = null;
                    _filter = anchor;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              const Text('Comentários').semiBold(),
              const Gap(6),
              Text(
                plan.openThreads == 1
                    ? '1 aberto'
                    : '${plan.openThreads} abertos',
              ).xSmall().muted(),
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
                Text('Filtrando: ${_label(widget.filter!)}').xSmall().muted(),
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
          child: threads.isEmpty
              ? Center(
                  child: const Text(
                    'Nenhum comentário aqui.\nUse "Comentar" em qualquer seção ou card.',
                    textAlign: TextAlign.center,
                  ).small().muted(),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [for (final t in threads) _thread(t)],
                ),
        ),
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
                      'Claude responde cada comentário e ajusta o plano. '
                      'Você resolve o que estiver ok.',
                    ).xSmall().muted(),
                  ],
                ),
        ),
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

  static String _label(String anchor) => switch (anchor) {
    'resumo' => 'Resumo',
    'arquitetura' => 'Arquitetura',
    'pastas' => 'Estrutura de pastas',
    'stack' => 'Stack',
    'cards' => 'Cards propostos',
    _ => 'Card #${anchor.substring(5)}',
  };
}
