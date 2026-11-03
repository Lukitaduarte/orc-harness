import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import 'agent_notices.dart';
import 'analytics_view.dart';
import 'catalog_view.dart';
import 'command_palette.dart';
import 'kanban.dart';
import 'panes.dart';
import 'plan_view.dart';
import 'search_dialog.dart';
import 'profile_panel.dart';
import 'sidebar.dart';

class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen(this.store, {super.key});

  final HarnessStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        // The profile belongs to a session; the kanban gets the full width.
        final showProfile =
            store.profilePanelOpen &&
            store.openProject == null &&
            !store.catalogOpen &&
            !store.analyticsOpen;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
                openCommandPalette(context, store),
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
                openCommandPalette(context, store),
            const SingleActivator(
              LogicalKeyboardKey.keyF,
              meta: true,
              shift: true,
            ): () =>
                showSearchDialog(context, store),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WorkspaceRail(store),
                  const VerticalDivider(),
                  Expanded(
                    child: ResizablePanel.horizontal(
                      key: ValueKey('main:$showProfile'),
                      children: [
                        ResizablePane(
                          initialSize: 280,
                          minSize: 220,
                          maxSize: 420,
                          child: Sidebar(store),
                        ),
                        ResizablePane.flex(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Toolbar(store),
                              const Divider(),
                              AgentNotices(store),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: switch (store.openProject) {
                                    _ when store.analyticsOpen => AnalyticsView(
                                      store,
                                    ),
                                    _ when store.catalogOpen => CatalogView(
                                      store,
                                    ),
                                    final p?
                                        when p.isPlanning ||
                                            (p.plan != null &&
                                                store.viewingPlan) =>
                                      PlanView(store, p, key: ValueKey(p.id)),
                                    final p? => KanbanView(store, p),
                                    null => PaneTree(store),
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (showProfile)
                          ResizablePane(
                            initialSize: 300,
                            minSize: 240,
                            maxSize: 420,
                            child: ProfilePanel(store),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar(this.store);

  final HarnessStore store;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      children: [
        SizedBox(
          width: 340,
          child: OutlineButton(
            alignment: Alignment.centerLeft,
            leading: const Icon(LucideIcons.search, size: 14),
            trailing: const Text('⌘K').xSmall().muted(),
            onPressed: () => openCommandPalette(context, store),
            child: const Text(
              'Buscar ou rodar um comando…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).small().muted(),
          ),
        ),
        if (store.openProject case final p?) ...[
          const Gap(8),
          GhostButton(
            leading: const Icon(LucideIcons.arrowLeft, size: 14),
            onPressed: () => store.openProjectView(null),
            child: const Text('Sessões').small(),
          ),
          const Text('/').small().muted(),
          const Gap(8),
          Text(p.name).small().semiBold(),
          if (p.isPlanning) ...[
            const Gap(8),
            const OutlineBadge(child: Text('plano')),
          ] else if (p.plan != null) ...[
            const Gap(12),
            _Toggle(
              'Execução',
              selected: !store.viewingPlan,
              onPressed: () => store.setViewingPlan(false),
            ),
            const Gap(4),
            _Toggle(
              'Plano',
              selected: store.viewingPlan,
              onPressed: () => store.setViewingPlan(true),
            ),
          ],
        ],
        if (store.analyticsOpen) ...[
          const Gap(8),
          GhostButton(
            leading: const Icon(LucideIcons.arrowLeft, size: 14),
            onPressed: () => store.openProjectView(null),
            child: const Text('Sessões').small(),
          ),
          const Text('/').small().muted(),
          const Gap(8),
          const Text('Uso').small().semiBold(),
        ],
        if (store.catalogOpen) ...[
          const Gap(8),
          GhostButton(
            leading: const Icon(LucideIcons.arrowLeft, size: 14),
            onPressed: () => store.openProjectView(null),
            child: const Text('Sessões').small(),
          ),
          const Text('/').small().muted(),
          const Gap(8),
          const Text('Catálogo').small().semiBold(),
        ],
        const Spacer(),
        GhostButton(
          density: ButtonDensity.icon,
          onPressed: store.toggleProfilePanel,
          child: const Icon(LucideIcons.panelRight, size: 16),
        ),
      ],
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, {required this.selected, required this.onPressed});

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => selected
      ? SecondaryButton(
          size: ButtonSize.small,
          onPressed: onPressed,
          child: Text(label),
        )
      : GhostButton(
          size: ButtonSize.small,
          onPressed: onPressed,
          child: Text(label),
        );
}
