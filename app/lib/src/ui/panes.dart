import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../model.dart';
import 'format.dart';

/// Renders the split tree. Each split is a resizable panel; each leaf a pane.
class PaneTree extends StatelessWidget {
  const PaneTree(this.store, {super.key});

  final HarnessStore store;

  @override
  Widget build(BuildContext context) => _node(store.layout);

  Widget _node(LayoutNode n) => switch (n) {
    LayoutLeaf() => Padding(
      padding: const EdgeInsets.all(4),
      child: _Pane(store, n),
    ),
    LayoutSplit() => _split(n),
  };

  Widget _split(LayoutSplit n) {
    final panes = [
      for (final c in n.children)
        ResizablePane.flex(key: ValueKey(c.id), minSize: 160, child: _node(c)),
    ];
    // A structural change (pane added or removed) rebuilds the panel fresh.
    final key = ValueKey('${n.id}:${n.children.map((c) => c.id).join(',')}');
    return n.horizontal
        ? ResizablePanel.horizontal(key: key, children: panes)
        : ResizablePanel.vertical(key: key, children: panes);
  }
}

class _Pane extends StatelessWidget {
  const _Pane(this.store, this.leaf);

  final HarnessStore store;
  final LayoutLeaf leaf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final focused = leaf.id == store.focusedLeafId;
    final session = leaf.sessionId == null
        ? null
        : store.session(leaf.sessionId!);
    return Listener(
      onPointerDown: (_) => store.focusLeaf(leaf.id),
      child: OutlinedContainer(
        borderColor: focused ? scheme.ring : scheme.border,
        borderWidth: focused ? 1.5 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, session),
            const Divider(),
            Expanded(
              child: session == null
                  ? _SessionPicker(store, leaf.id)
                  : TerminalView(session),
            ),
            if (session != null) ...[
              const Divider(),
              _footer(context, session),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Session? s) => SizedBox(
    height: 36,
    child: Padding(
      padding: const EdgeInsets.only(left: 10, right: 4),
      child: Row(
        children: [
          if (s != null) ...[
            StatusDot(sessionStateColor(context, s.state)),
            const Gap(8),
            Text(s.name).small().semiBold(),
            const Gap(8),
            const Icon(LucideIcons.gitBranch, size: 12),
            const Gap(4),
            Flexible(
              child: Text(
                s.branch,
                overflow: TextOverflow.ellipsis,
              ).xSmall().muted(),
            ),
            const Gap(8),
            SecondaryBadge(child: Text(s.model)),
          ] else
            const Text('Pane vazio').small().muted(),
          const Spacer(),
          _iconButton(
            LucideIcons.columns2,
            'Dividir lado a lado',
            () => store.split(leaf.id, horizontal: true),
          ),
          _iconButton(
            LucideIcons.rows2,
            'Dividir em cima e embaixo',
            () => store.split(leaf.id, horizontal: false),
          ),
          _iconButton(LucideIcons.x, 'Fechar pane', () => store.close(leaf.id)),
        ],
      ),
    ),
  );

  Widget _footer(BuildContext context, Session s) {
    final acc = store.account(s.accountId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${acc.email} · ${formatTokens(s.tokens)} tokens · ${formatUsd(s.costUsd)}',
              overflow: TextOverflow.ellipsis,
            ).xSmall().muted(),
          ),
          const Gap(8),
          Text('${s.fiveHourShare.round()}% da janela de 5h').xSmall().muted(),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, String tip, VoidCallback onPressed) =>
      Tooltip(
        tooltip: (context) => TooltipContainer(child: Text(tip)),
        child: GhostButton(
          density: ButtonDensity.icon,
          size: ButtonSize.small,
          onPressed: onPressed,
          child: Icon(icon, size: 14),
        ),
      );
}

/// Fake terminal for phase 0. Phase 1 swaps it for a renderer of the cell grid
/// the daemon emulates.
class TerminalView extends StatelessWidget {
  const TerminalView(this.session, {super.key});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget line(TerminalLine l) {
      final text = Text(l.text).mono().xSmall();
      return switch (l.kind) {
        LineKind.prompt => text.semiBold(),
        LineKind.assistant => text,
        LineKind.tool => text.medium(color: scheme.primary),
        LineKind.result => text.muted(),
        LineKind.dim => text.italic().muted(),
      };
    }

    return Container(
      color: scheme.background,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final l in session.lines)
            Padding(padding: const EdgeInsets.only(bottom: 2), child: line(l)),
          if (session.state == SessionState.starting)
            const Text('↻ reiniciando com --resume…').mono().xSmall().muted(),
        ],
      ),
    );
  }
}

class _SessionPicker extends StatelessWidget {
  const _SessionPicker(this.store, this.leafId);

  final HarnessStore store;
  final String leafId;

  @override
  Widget build(BuildContext context) {
    final hidden = store.hiddenSessions;
    return Center(
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Abrir neste pane').small().semiBold(),
            const Gap(8),
            for (final s in hidden)
              OutlineButton(
                alignment: Alignment.centerLeft,
                leading: StatusDot(sessionStateColor(context, s.state)),
                onPressed: () => store.attach(leafId, s.id),
                child: Text(s.name),
              ),
            if (hidden.isNotEmpty) const Gap(4),
            PrimaryButton(
              leading: const Icon(LucideIcons.plus, size: 16),
              onPressed: store.newSession,
              child: const Text('Nova sessão'),
            ),
          ],
        ),
      ),
    );
  }
}
