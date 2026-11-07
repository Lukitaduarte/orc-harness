import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../model.dart';
import 'connect_dialog.dart';
import 'format.dart';
import 'repos.dart';
import 'confirm.dart';
import 'workspace_dialogs.dart';
import 'new_plan_dialog.dart';

/// Narrow rail with one avatar per workspace, like Slack or Discord.
class WorkspaceRail extends StatelessWidget {
  const WorkspaceRail(this.store, {super.key});

  final HarnessStore store;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      color: scheme.muted,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          for (final ws in store.workspaces) ...[
            Tooltip(
              tooltip: (context) => TooltipContainer(child: Text(ws.name)),
              alignment: Alignment.centerLeft,
              anchorAlignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => store.selectWorkspace(ws.id),
                // Right click: rename, accounts, delete.
                onSecondaryTap: store.isLiveWorkspace(ws.id)
                    ? () => showWorkspaceDialog(context, store, editing: ws)
                    : null,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      width: 2,
                      color: ws.id == store.workspaceId
                          ? scheme.primary
                          : Colors.transparent,
                    ),
                  ),
                  child: Avatar(
                    initials: ws.initials,
                    size: 34,
                    backgroundColor: scheme.background,
                  ),
                ),
              ),
            ),
            const Gap(8),
          ],
          if (store.daemon != null)
            Tooltip(
              tooltip: (context) =>
                  TooltipContainer(child: Text(context.l10n.shellNewWorkspace)),
              alignment: Alignment.centerLeft,
              anchorAlignment: Alignment.centerRight,
              child: GhostButton(
                density: ButtonDensity.icon,
                onPressed: () => showWorkspaceDialog(context, store),
                child: const Icon(LucideIcons.plus, size: 18),
              ),
            ),
          const Spacer(),
          Tooltip(
            tooltip: (context) =>
                TooltipContainer(child: Text(context.l10n.shellUsageAndCost)),
            alignment: Alignment.centerLeft,
            anchorAlignment: Alignment.centerRight,
            child: store.analyticsOpen
                ? SecondaryButton(
                    density: ButtonDensity.icon,
                    onPressed: store.openAnalytics,
                    child: const Icon(LucideIcons.chartColumn, size: 18),
                  )
                : GhostButton(
                    density: ButtonDensity.icon,
                    onPressed: store.openAnalytics,
                    child: const Icon(LucideIcons.chartColumn, size: 18),
                  ),
          ),
          const Gap(4),
          Tooltip(
            tooltip: (context) =>
                TooltipContainer(child: Text(context.l10n.shellCatalogTip)),
            alignment: Alignment.centerLeft,
            anchorAlignment: Alignment.centerRight,
            child: store.catalogOpen
                ? SecondaryButton(
                    density: ButtonDensity.icon,
                    onPressed: store.openCatalog,
                    child: const Icon(LucideIcons.blocks, size: 18),
                  )
                : GhostButton(
                    density: ButtonDensity.icon,
                    onPressed: store.openCatalog,
                    child: const Icon(LucideIcons.blocks, size: 18),
                  ),
          ),
          const Gap(4),
          GhostButton(
            density: ButtonDensity.icon,
            onPressed: () => showConnectDialog(context, store),
            child: const Icon(LucideIcons.settings, size: 18),
          ),
        ],
      ),
    );
  }
}

class Sidebar extends StatelessWidget {
  const Sidebar(this.store, {super.key});

  final HarnessStore store;

  @override
  Widget build(BuildContext context) {
    final accounts = store.workspaceAccounts;
    final sessions = store.workspaceSessions;
    final focused = store.focusedSession;
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(child: Text(store.workspace.name).large().semiBold()),
            if (store.isLive)
              GhostButton(
                density: ButtonDensity.icon,
                size: ButtonSize.small,
                onPressed: () => showWorkspaceDialog(
                  context,
                  store,
                  editing: store.workspace,
                ),
                child: const Icon(LucideIcons.settings2, size: 14),
              ),
          ],
        ),
        Text(
          l10n.shellSidebarCounts(accounts.length, sessions.length),
        ).xSmall().muted(),
        const Gap(16),
        _SectionLabel(
          l10n.shellAccounts,
          addTip: l10n.shellNewAccount,
          onAdd: store.isLive
              ? () => showNewAccountDialog(context, store)
              : null,
        ),
        for (final a in accounts)
          _AccountCard(
            a,
            store.now,
            onMenu: a.live ? () => _accountActions(context, a) : null,
          ),
        const Gap(8),
        _SectionLabel(
          l10n.shellSessions,
          addTip: l10n.shellNewSession,
          onAdd: store.newSession,
        ),
        for (final s in sessions)
          _RowActions(
            tip: l10n.shellDeleteSession,
            icon: LucideIcons.trash2,
            onAction: () async {
              if (await confirm(
                context,
                l10n.shellDeleteSessionTitle(s.name),
                l10n.shellDeleteSessionBody,
                l10n.shellDelete,
              )) {
                store.deleteSession(s.id);
              }
            },
            child: _SessionRow(
              s,
              selected: store.openProjectId == null && s.id == focused?.id,
              onTap: () => store.showSession(s.id),
            ),
          ),
        const Gap(16),
        if (store.isLive) ...[
          _SectionLabel(
            l10n.shellRepositories,
            addTip: l10n.shellAddRepository,
            onAdd: () => showAddRepo(context, store),
          ),
          RepoSection(store),
          const Gap(16),
        ],
        _SectionLabel(
          l10n.shellPlans,
          addTip: l10n.shellNewPlan,
          onAdd: () => showNewPlanDialog(context, store),
        ),
        for (final p in store.workspaceProjects)
          _RowActions(
            tip: l10n.shellDeletePlan,
            icon: LucideIcons.trash2,
            onAction: () async {
              final running = p.cards.any(
                (c) =>
                    c.state == CardState.running || c.state == CardState.review,
              );
              if (await confirm(
                context,
                l10n.shellDeletePlanTitle(p.name),
                running
                    ? l10n.shellDeletePlanBodyRunning
                    : l10n.shellDeletePlanBody,
                l10n.shellDelete,
              )) {
                store.deleteProject(p);
              }
            },
            child: _ProjectRow(
              p,
              selected: p.id == store.openProjectId,
              onTap: () => store.openProjectView(p.id),
            ),
          ),
      ],
    );
  }

  /// What you can do with an account: log out, take it out.
  Future<void> _accountActions(BuildContext context, Account a) async {
    final l10n = context.l10n;
    final choice = await showOverlay<String>(
      context,
      DialogConfiguration<String>(
        builder: (context) {
          final theme = Theme.of(context);
          return ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ModalBackdrop(
              borderRadius: theme.borderRadiusXl,
              child: OutlinedContainer(
                backgroundColor: theme.colorScheme.popover,
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.shellAccountTitle(a.email)).large().semiBold(),
                    const Gap(12),
                    OutlineButton(
                      leading: const Icon(LucideIcons.logOut, size: 14),
                      onPressed: () => closeOverlay(context, 'logout'),
                      child: Text(l10n.shellLogoutButton),
                    ),
                    const Gap(4),
                    Text(l10n.shellLogoutHint).xSmall().muted(),
                    const Gap(12),
                    DestructiveButton(
                      leading: const Icon(LucideIcons.userMinus, size: 14),
                      onPressed: () => closeOverlay(context, 'remove'),
                      child: Text(l10n.shellRemoveFromHarness),
                    ),
                    const Gap(4),
                    Text(l10n.shellRemoveHint).xSmall().muted(),
                    const Gap(16),
                    OutlineButton(
                      onPressed: () => closeOverlay(context, null),
                      child: Text(l10n.shellCancel),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).future;
    if (!context.mounted) return;
    switch (choice) {
      case 'logout':
        if (await confirm(
          context,
          l10n.shellLogoutTitle(a.email),
          a.id == 'default'
              ? l10n.shellLogoutDefaultBody
              : l10n.shellLogoutBody,
          l10n.shellLogout,
        )) {
          store.logoutAccount(a.id);
        }
      case 'remove':
        if (await confirm(
          context,
          l10n.shellRemoveTitle(a.email),
          l10n.shellRemoveBody,
          l10n.shellRemove,
        )) {
          store.removeAccount(a.id);
        }
    }
  }
}

/// A section title with an optional + on the other side.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.onAdd, this.addTip});

  final String text;
  final VoidCallback? onAdd;
  final String? addTip;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(text.toUpperCase()).xSmall().semiBold().muted(),
        if (onAdd != null)
          Tooltip(
            tooltip: (context) => TooltipContainer(child: Text(addTip ?? '')),
            child: GhostButton(
              density: ButtonDensity.icon,
              size: ButtonSize.small,
              onPressed: onAdd,
              child: const Icon(LucideIcons.plus, size: 14),
            ),
          ),
      ],
    ),
  );
}

/// A row with an action icon on hover; right click (or long press on the
/// phone) does the same.
class _RowActions extends StatefulWidget {
  const _RowActions({
    required this.child,
    required this.onAction,
    required this.tip,
    this.icon = LucideIcons.ellipsis,
  });

  final Widget child;
  final VoidCallback? onAction;
  final String tip;
  final IconData icon;

  @override
  State<_RowActions> createState() => _RowActionsState();
}

class _RowActionsState extends State<_RowActions> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.onAction;
    if (action == null) return widget.child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onSecondaryTap: action,
        onLongPress: action,
        child: Stack(
          children: [
            widget.child,
            if (_hover)
              Positioned(
                right: 4,
                top: 4,
                child: Tooltip(
                  tooltip: (context) =>
                      TooltipContainer(child: Text(widget.tip)),
                  child: GhostButton(
                    density: ButtonDensity.icon,
                    size: ButtonSize.small,
                    onPressed: action,
                    child: Icon(widget.icon, size: 13),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard(this.account, this.now, {this.onMenu});

  final Account account;
  final DateTime now;

  /// Log out / remove (live accounts).
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final age = now.difference(account.readAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedContainer(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✻ name … (space between)
            Row(
              children: [
                // Claude Code's own mark (the ✻ of its terminal).
                Tooltip(
                  tooltip: (context) =>
                      const TooltipContainer(child: Text('Claude Code')),
                  child: const Text(
                    '✻',
                    style: TextStyle(
                      color: Color(0xFFD97757),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: Text(
                    account.email,
                    overflow: TextOverflow.ellipsis,
                  ).small().medium(),
                ),
                if (onMenu != null)
                  GhostButton(
                    density: ButtonDensity.icon,
                    size: ButtonSize.small,
                    onPressed: onMenu,
                    child: const Icon(LucideIcons.ellipsis, size: 14),
                  ),
              ],
            ),
            const Gap(10),
            if (!account.hasReading)
              Text(context.l10n.shellNoReadingYet).xSmall().muted()
            else ...[
              QuotaMeter('5h', account.fiveHour, now),
              const Gap(8),
              QuotaMeter('7d', account.sevenDay, now),
            ],
            // Idle accounts keep their last reading instead of dropping to zero.
            if (account.hasReading && age.inMinutes >= 5) ...[
              const Gap(6),
              Text(
                context.l10n.shellUpdatedAgo(formatDuration(age)),
              ).xSmall().muted(),
            ],
          ],
        ),
      ),
    );
  }
}

class QuotaMeter extends StatelessWidget {
  const QuotaMeter(this.label, this.window, this.now, {super.key});

  final String label;
  final QuotaWindow window;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final color = quotaColor(context, window.usedPercent);
    final exhaust = window.timeToExhaust(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 22, child: Text(label).xSmall().semiBold()),
            Expanded(
              child: LinearProgressIndicator(
                value: window.usedPercent / 100,
                color: color,
                minHeight: 6,
                disableAnimation: true,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '${window.usedPercent.round()}%',
                textAlign: TextAlign.right,
              ).xSmall().semiBold(),
            ),
          ],
        ),
        const Gap(2),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: exhaust == null
              ? Text(
                  context.l10n.shellResetIn(
                    formatDuration(window.resetsAt.difference(now)),
                  ),
                ).xSmall().muted()
              : Text(
                  context.l10n.shellExhaustsIn(formatDuration(exhaust)),
                ).xSmall().medium(color: color),
        ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow(
    this.session, {
    required this.selected,
    required this.onTap,
  });

  final Session session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? scheme.accent : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              StatusDot(sessionStateColor(context, session.state)),
              const Gap(8),
              Text(session.name).small().medium(),
              const Gap(6),
              Expanded(
                child: Text(
                  session.branch,
                  overflow: TextOverflow.ellipsis,
                ).xSmall().muted(),
              ),
              const Gap(8),
              Text(sessionStateLabel(session.state)).xSmall().muted(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow(
    this.project, {
    required this.selected,
    required this.onTap,
  });

  final Project project;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.accent : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.kanban, size: 14),
            const Gap(8),
            Expanded(
              child: Text(
                project.name,
                overflow: TextOverflow.ellipsis,
              ).small(),
            ),
            project.isPlanning
                ? OutlineBadge(child: Text(context.l10n.shellPlanBadge))
                : Text(
                    '${project.doneCount}/${project.cards.length}',
                  ).xSmall().muted(),
          ],
        ),
      ),
    ),
  );
}
