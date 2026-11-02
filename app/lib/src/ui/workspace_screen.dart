import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import 'panes.dart';
import 'profile_panel.dart';
import 'sidebar.dart';

class WorkspaceScreen extends StatelessWidget {
  const WorkspaceScreen(this.store, {super.key});

  final HarnessStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WorkspaceRail(store),
            const VerticalDivider(),
            Expanded(
              child: ResizablePanel.horizontal(
                key: ValueKey('main:${store.profilePanelOpen}'),
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
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: PaneTree(store),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (store.profilePanelOpen)
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
            onPressed: () {},
            child: const Text(
              'Buscar ou rodar um comando…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ).small().muted(),
          ),
        ),
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
