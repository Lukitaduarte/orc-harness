import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../model.dart';
import 'format.dart';

class _Cmd {
  const _Cmd(this.group, this.title, this.icon, this.run, {this.hint});

  final String group;
  final String title;
  final IconData icon;
  final VoidCallback run;
  final String? hint;
}

/// ⌘K: every action of the current screen, searchable by name.
Future<void> openCommandPalette(BuildContext context, HarnessStore store) {
  return showCommandDialog<void>(
    context: context,
    debounceDuration: const Duration(milliseconds: 60),
    builder: (dialogContext, query) async* {
      final sans = Theme.of(dialogContext).typography.sans;
      final q = foldAccents(query ?? '');
      final matches = _commands(store).where(
        (c) => q.isEmpty || foldAccents('${c.group} ${c.title}').contains(q),
      );
      final groups = <String, List<_Cmd>>{};
      for (final c in matches) {
        groups.putIfAbsent(c.group, () => []).add(c);
      }
      yield [
        for (final MapEntry(key: group, value: cmds) in groups.entries)
          CommandCategory(
            title: Text(group),
            children: [
              for (final c in cmds)
                CommandItem(
                  leading: Icon(c.icon, size: 16),
                  // CommandItem resets the text style to a bare color; keep
                  // the app's font family.
                  title: Text(c.title, style: sans).small(),
                  trailing: c.hint == null
                      ? null
                      : Text(c.hint!, style: sans).xSmall().muted(),
                  onTap: () {
                    closeOverlay(dialogContext);
                    c.run();
                  },
                ),
            ],
          ),
      ];
    },
  );
}

List<_Cmd> _commands(HarnessStore store) {
  final focused = store.focusedSession;
  final leaf = store.focusedLeafId;
  final project = store.openProject;
  return [
    for (final s in store.workspaceSessions)
      _Cmd(
        'Sessões',
        'Ir para ${s.name}',
        LucideIcons.terminal,
        () => store.showSession(s.id),
        hint: sessionStateLabel(s.state),
      ),
    _Cmd('Sessões', 'Nova sessão', LucideIcons.plus, store.newSession),
    if (project == null) ...[
      _Cmd(
        'Panes',
        'Dividir lado a lado',
        LucideIcons.columns2,
        () => store.split(leaf, horizontal: true),
      ),
      _Cmd(
        'Panes',
        'Dividir em cima e embaixo',
        LucideIcons.rows2,
        () => store.split(leaf, horizontal: false),
      ),
      _Cmd('Panes', 'Fechar pane', LucideIcons.x, () => store.close(leaf)),
    ],
    _Cmd(
      'Panes',
      store.profilePanelOpen
          ? 'Ocultar painel de perfil'
          : 'Mostrar painel de perfil',
      LucideIcons.panelRight,
      store.toggleProfilePanel,
    ),
    for (final p in store.workspaceProjects) ...[
      _Cmd(
        'Projetos',
        'Abrir ${p.name}',
        LucideIcons.kanban,
        () => store.openProjectView(p.id),
        hint: '${p.doneCount}/${p.cards.length}',
      ),
      if (store.readyCards(p).isNotEmpty && store.canRun(p))
        _Cmd(
          'Projetos',
          'Executar cards prontos de ${p.name}',
          LucideIcons.play,
          () => store.runReady(p),
          hint: store.readyCards(p).length == 1
              ? '1 pronto'
              : '${store.readyCards(p).length} prontos',
        ),
    ],
    if (project != null)
      _Cmd(
        'Projetos',
        'Voltar para as sessões',
        LucideIcons.terminal,
        () => store.openProjectView(null),
      ),
    if (focused != null) ...[
      for (final item in store.catalog)
        _Cmd(
          'Perfil de ${focused.name}',
          '${focused.draftItems.contains(item.id) ? 'Desligar' : 'Ligar'} ${item.name}',
          switch (item.kind) {
            CatalogKind.skill => LucideIcons.sparkles,
            CatalogKind.mcp => LucideIcons.plug,
            CatalogKind.env => LucideIcons.keyRound,
          },
          () => store.toggleItem(focused, item.id),
          hint: switch (item.kind) {
            CatalogKind.skill => 'skill',
            CatalogKind.mcp => 'MCP',
            CatalogKind.env => 'env',
          },
        ),
      if (focused.hasPendingChanges)
        _Cmd(
          'Perfil de ${focused.name}',
          'Aplicar mudanças (reinicia com --resume)',
          LucideIcons.refreshCw,
          () => store.applyDraft(focused),
        ),
    ],
    for (final ws in store.workspaces)
      if (ws.id != store.workspaceId)
        _Cmd(
          'Workspaces',
          'Trocar para ${ws.name}',
          LucideIcons.arrowLeftRight,
          () => store.selectWorkspace(ws.id),
        ),
  ];
}
