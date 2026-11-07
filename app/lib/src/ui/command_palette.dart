import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../model.dart';
import 'format.dart';
import 'new_plan_dialog.dart';
import 'search_dialog.dart';
import 'template_editor.dart';

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
      final matches = _commands(context, store).where(
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

List<_Cmd> _commands(BuildContext context, HarnessStore store) {
  final focused = store.focusedSession;
  final leaf = store.focusedLeafId;
  final project = store.openProject;
  final t = context.l10n;
  return [
    for (final s in store.workspaceSessions)
      _Cmd(
        t.toolsGroupSessions,
        t.toolsGoTo(s.name),
        LucideIcons.terminal,
        () => store.showSession(s.id),
        hint: sessionStateLabel(s.state),
      ),
    _Cmd(
      t.toolsGroupSessions,
      t.toolsNewSession,
      LucideIcons.plus,
      store.newSession,
    ),
    if (project == null) ...[
      _Cmd(
        t.toolsGroupPanes,
        t.toolsSplitSideBySide,
        LucideIcons.columns2,
        () => store.split(leaf, horizontal: true),
      ),
      _Cmd(
        t.toolsGroupPanes,
        t.toolsSplitTopBottom,
        LucideIcons.rows2,
        () => store.split(leaf, horizontal: false),
      ),
      _Cmd(
        t.toolsGroupPanes,
        t.toolsClosePane,
        LucideIcons.x,
        () => store.close(leaf),
      ),
    ],
    _Cmd(
      t.toolsGroupPanes,
      store.profilePanelOpen
          ? t.toolsHideProfilePanel
          : t.toolsShowProfilePanel,
      LucideIcons.panelRight,
      store.toggleProfilePanel,
    ),
    for (final p in store.workspaceProjects) ...[
      _Cmd(
        t.toolsGroupProjects,
        p.isPlanning ? t.toolsOpenPlanOf(p.name) : t.toolsOpenNamed(p.name),
        LucideIcons.kanban,
        () => store.openProjectView(p.id),
        hint: p.isPlanning
            ? t.toolsOpenComments(p.plan!.openThreads)
            : '${p.doneCount}/${p.cards.length}',
      ),
      if (store.readyCards(p).isNotEmpty && store.canRun(p))
        _Cmd(
          t.toolsGroupProjects,
          t.toolsRunReadyCards(p.name),
          LucideIcons.play,
          () => store.runReady(p),
          hint: t.toolsReadyCount(store.readyCards(p).length),
        ),
    ],
    if (project?.plan case final plan?
        when plan.threads.any((t) => t.awaitingAgent) && !plan.reviewing)
      _Cmd(
        t.toolsGroupProjects,
        t.toolsRequestReview,
        LucideIcons.sparkles,
        () => store.requestPlanReview(plan),
      ),
    _Cmd(
      t.toolsGroupProjects,
      t.toolsNewPlanFromTemplate,
      LucideIcons.sparkles,
      () => showNewPlanDialog(context, store),
    ),
    _Cmd(
      t.toolsGroupProjects,
      t.toolsImportPlan,
      LucideIcons.fileText,
      () => showNewPlanDialog(context, store, importing: true),
    ),
    _Cmd(
      t.toolsGroupCatalog,
      t.toolsNewPlanTemplate,
      LucideIcons.filePlus,
      () => showTemplateEditor(context, store),
    ),
    _Cmd(
      t.toolsGroupCode,
      t.toolsSearchCodeCmd,
      LucideIcons.search,
      () => showSearchDialog(context, store),
    ),
    _Cmd(
      t.toolsGroupUsage,
      t.toolsOpenUsage,
      LucideIcons.chartColumn,
      store.openAnalytics,
    ),
    _Cmd(
      t.toolsGroupCatalog,
      t.toolsOpenCatalog,
      LucideIcons.blocks,
      store.openCatalog,
    ),
    if (project != null)
      _Cmd(
        t.toolsGroupProjects,
        t.toolsBackToSessions,
        LucideIcons.terminal,
        () => store.openProjectView(null),
      ),
    if (focused != null) ...[
      for (final item in store.catalog)
        _Cmd(
          t.toolsGroupProfileOf(focused.name),
          focused.draftItems.contains(item.id)
              ? t.toolsTurnOff(item.name)
              : t.toolsTurnOn(item.name),
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
          t.toolsGroupProfileOf(focused.name),
          t.toolsApplyChanges,
          LucideIcons.refreshCw,
          () => store.applyDraft(focused),
        ),
    ],
    for (final ws in store.workspaces)
      if (ws.id != store.workspaceId)
        _Cmd(
          t.toolsGroupWorkspaces,
          t.toolsSwitchTo(ws.name),
          LucideIcons.arrowLeftRight,
          () => store.selectWorkspace(ws.id),
        ),
  ];
}
