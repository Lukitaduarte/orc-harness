import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../model.dart';
import '../live/grid.dart';
import '../live/live_terminal.dart';
import 'browser_pane.dart';
import 'code_pane.dart';
import 'orc_sprite.dart';
import 'diff_dialog.dart';
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
        ResizablePane.flex(key: ValueKey(c.id), minSize: 220, child: _node(c)),
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
    final browser = HarnessStore.isBrowserPane(leaf.sessionId)
        ? leaf.sessionId!.substring(HarnessStore.browserPrefix.length)
        : null;
    final code = HarnessStore.isCodePane(leaf.sessionId)
        ? leaf.sessionId!.substring(HarnessStore.codePrefix.length)
        : null;
    final session = leaf.sessionId == null || browser != null || code != null
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
            _header(context, session, browser: browser, code: code),
            const Divider(),
            Expanded(
              child: code != null && store.daemon != null
                  ? CodePane(daemon: store.daemon!, sessionId: code)
                  : browser != null && store.daemon != null
                  ? BrowserPane(
                      daemon: store.daemon!,
                      profile: browser,
                      focused: focused,
                    )
                  : session == null
                  ? _SessionPicker(store, leaf.id)
                  : session.live
                  ? _live(session, focused)
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

  /// A real session: the daemon's grid, keys back as input.
  Widget _live(Session s, bool focused) {
    final d = store.daemon!;
    final grid = d.grids[s.id];
    Widget terminal(GridState? g) => LiveTerminal(
      grid: g,
      focused: focused,
      onInput: (data) => d.input(s.id, data),
      onResize: (cols, rows) => d.resize(s.id, cols, rows),
    );
    return grid == null
        ? terminal(null)
        : ListenableBuilder(
            listenable: grid,
            builder: (context, _) => terminal(grid.state),
          );
  }

  Widget _header(
    BuildContext context,
    Session? s, {
    String? browser,
    String? code,
  }) => SizedBox(
    height: 36,
    child: Padding(
      padding: const EdgeInsets.only(left: 10, right: 4),
      // Narrow panes keep the title and the buttons; details go first.
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 420;
          return Row(
            children: [
              // The title takes what is left; the buttons stay at the edge.
              Expanded(
                child: Row(
                  children: [
                    if (s != null) ...[
                      StatusDot(sessionStateColor(context, s.state)),
                      const Gap(8),
                      Flexible(
                        child: Text(
                          s.name,
                          overflow: TextOverflow.ellipsis,
                        ).small().semiBold(),
                      ),
                      if (wide) ...[
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
                      ],
                    ] else if (code != null) ...[
                      const Icon(LucideIcons.code, size: 14),
                      const Gap(8),
                      Flexible(
                        child: Text(
                          context.l10n.shellCodePaneTitle(
                            store.sessions
                                    .where((x) => x.id == code)
                                    .map((x) => x.name)
                                    .firstOrNull ??
                                code,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ).small().semiBold(),
                      ),
                    ] else if (browser != null) ...[
                      const Icon(LucideIcons.globe, size: 14),
                      const Gap(8),
                      Flexible(
                        child: Text(
                          context.l10n.shellWorkspaceBrowser,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ).small().semiBold(),
                      if (wide)
                        if (store.daemon?.browserOf(browser).usedBy
                            case final s?) ...[
                          const Gap(8),
                          OutlineBadge(
                            child: Text(
                              context.l10n.shellInUseBy(
                                store.daemon!.sessionLabel(s),
                              ),
                            ),
                          ),
                        ],
                    ] else
                      Flexible(
                        child: Text(
                          context.l10n.shellEmptyPane,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ).small().muted(),
                  ],
                ),
              ),
              // A worktree session: its changes and PR.
              if (s != null &&
                  s.live &&
                  (store.daemon?.sessions.any(
                        (l) => l.id == s.id && l.projectId != null,
                      ) ??
                      false))
                Builder(
                  builder: (context) => _iconButton(
                    LucideIcons.gitCompare,
                    context.l10n.shellChangesAndPr,
                    () => showDiffDialog(context, store, s.id),
                  ),
                ),
              if (s != null && s.live)
                _iconButton(
                  LucideIcons.code,
                  context.l10n.shellCodeTip,
                  () => store.openCode(leaf.id, s.id),
                ),
              _iconButton(
                LucideIcons.columns2,
                context.l10n.shellSplitSideBySide,
                () => store.split(leaf.id, horizontal: true),
              ),
              _iconButton(
                LucideIcons.rows2,
                context.l10n.shellSplitTopBottom,
                () => store.split(leaf.id, horizontal: false),
              ),
              _iconButton(
                LucideIcons.x,
                context.l10n.shellClosePane,
                () => store.close(leaf.id),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _footer(BuildContext context, Session s) {
    final acc = store.account(s.accountId);
    final l10n = context.l10n;
    final tokensCost = l10n.shellTokensCost(
      formatTokens(s.tokens),
      formatUsd(s.costUsd),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.live
                  ? '${acc.email} · ${s.branch}'
                  : '${acc.email} · $tokensCost',
              overflow: TextOverflow.ellipsis,
            ).xSmall().muted(),
          ),
          const Gap(8),
          // Live: tokens and cost from Claude Code's metrics.
          Text(
            s.live
                ? tokensCost
                : l10n.shellFiveHourShare(s.fiveHourShare.round()),
          ).xSmall().muted(),
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
            Text(
              context.l10n.shellRestartingResumeLine,
            ).mono().xSmall().muted(),
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
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The orc, ready for the next job.
            Center(child: OrcSprite(scale: 3, says: context.l10n.orcReady)),
            const Gap(16),
            Text(context.l10n.shellOpenInPane).small().semiBold(),
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
              child: Text(context.l10n.shellNewSession),
            ),
            if (store.isLive) ...[
              const Gap(4),
              OutlineButton(
                leading: const Icon(LucideIcons.globe, size: 16),
                onPressed: () => store.openBrowser(leafId),
                child: Text(context.l10n.shellWorkspaceBrowser),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
