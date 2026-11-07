import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../live/daemon_client.dart';
import '../model.dart';
import 'agent_notices.dart';
import 'confirm.dart';
import 'connect_dialog.dart';
import 'format.dart';
import 'live_input_bar.dart';
import 'panes.dart' show TerminalView;
import 'plan_view.dart';
import 'sidebar.dart' show QuotaMeter;
import '../live/live_terminal.dart';

/// The app on a phone: quotas always on top, then sessions or plans; a
/// session opens full screen with an input bar for the soft keyboard.
class MobileShell extends StatefulWidget {
  const MobileShell(this.store, {super.key});

  final HarnessStore store;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  String? _session;
  String? _project;
  bool _plans = false;

  HarnessStore get store => widget.store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final session = store.workspaceSessions
          .where((s) => s.id == _session)
          .firstOrNull;
      if (session != null) {
        return _SessionScreen(
          store,
          session,
          onBack: () => setState(() => _session = null),
        );
      }
      final project = store.workspaceProjects
          .where((p) => p.id == _project)
          .firstOrNull;
      if (project != null) {
        return _ProjectScreen(
          store,
          project,
          onBack: () => setState(() => _project = null),
        );
      }
      return _home(context);
    },
  );

  Widget _home(BuildContext context) {
    final d = store.daemon;
    return Scaffold(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
              child: Row(
                children: [
                  const Text('orc').large().semiBold(),
                  const Gap(10),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final w in store.workspaces)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: w.id == store.workspaceId
                                  ? SecondaryButton(
                                      size: ButtonSize.small,
                                      onPressed: () {},
                                      child: Text(w.name),
                                    )
                                  : GhostButton(
                                      size: ButtonSize.small,
                                      onPressed: () =>
                                          store.selectWorkspace(w.id),
                                      child: Text(w.name),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (d != null)
                    GhostButton(
                      density: ButtonDensity.icon,
                      onPressed: () => showConnectDialog(context, store),
                      child: Icon(
                        d.status == LinkStatus.connected
                            ? LucideIcons.link
                            : LucideIcons.unlink,
                        size: 16,
                      ),
                    ),
                ],
              ),
            ),
            // Quota is always in sight.
            for (final a in store.workspaceAccounts)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      a.email,
                      overflow: TextOverflow.ellipsis,
                    ).xSmall().medium(),
                    const Gap(4),
                    if (!a.hasReading)
                      Text(context.l10n.devNoQuotaReading).xSmall().muted()
                    else ...[
                      QuotaMeter('5h', a.fiveHour, store.now),
                      const Gap(4),
                      QuotaMeter('7d', a.sevenDay, store.now),
                    ],
                  ],
                ),
              ),
            AgentNotices(store),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _tab(
                      context.l10n.devSessions,
                      !_plans,
                      () => setState(() => _plans = false),
                    ),
                  ),
                  const Gap(6),
                  Expanded(
                    child: _tab(
                      context.l10n.devPlans,
                      _plans,
                      () => setState(() => _plans = true),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(child: _plans ? _planList() : _sessionList(context)),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, bool on, VoidCallback onPressed) => on
      ? SecondaryButton(onPressed: onPressed, child: Text(label))
      : GhostButton(onPressed: onPressed, child: Text(label));

  Widget _sessionList(BuildContext context) {
    final sessions = store.workspaceSessions;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final s in sessions)
          _Tile(
            leading: StatusDot(sessionStateColor(context, s.state)),
            title: s.name,
            subtitle: '${s.branch} · ${s.model}',
            onTap: () => setState(() => _session = s.id),
            onLongPress: () async {
              if (await confirm(
                context,
                context.l10n.devDeleteSessionTitle(s.name),
                context.l10n.devDeleteSessionBody,
                context.l10n.devDelete,
              )) {
                store.deleteSession(s.id);
              }
            },
          ),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(context.l10n.devNoSessions),
          ),
        const Gap(8),
        OutlineButton(
          leading: const Icon(LucideIcons.plus, size: 16),
          onPressed: () {
            store.newSession();
            final s = store.focusedSession;
            if (s != null) setState(() => _session = s.id);
          },
          child: Text(context.l10n.devNewSession),
        ),
      ],
    );
  }

  Widget _planList() => ListView(
    padding: const EdgeInsets.all(8),
    children: [
      for (final p in store.workspaceProjects)
        _Tile(
          leading: Icon(
            p.isPlanning ? LucideIcons.fileText : LucideIcons.kanban,
            size: 16,
          ),
          title: p.name,
          subtitle: p.isPlanning
              ? context.l10n.devPlanReviewProgress(
                  p.plan!.approvedCount,
                  p.plan!.sections.length,
                  p.plan!.openThreads,
                )
              : context.l10n.devCardsDone(p.doneCount, p.cards.length),
          onTap: () => setState(() => _project = p.id),
          onLongPress: () async {
            if (await confirm(
              context,
              context.l10n.devDeletePlanTitle(p.name),
              context.l10n.devDeletePlanBody,
              context.l10n.devDelete,
            )) {
              store.deleteProject(p);
            }
          },
        ),
      if (store.workspaceProjects.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.devNoPlans),
        ),
    ],
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onLongPress,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: OutlinedContainer(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            leading,
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                  ).small().semiBold(),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                  ).xSmall().muted(),
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 16),
          ],
        ),
      ),
    ),
  );
}

/// One session full screen: its terminal (sized to the phone) and an input
/// bar, with the account's quota in the header.
class _SessionScreen extends StatelessWidget {
  const _SessionScreen(this.store, this.session, {required this.onBack});

  final HarnessStore store;
  final Session session;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final acc = store.account(s.accountId);
    final d = store.daemon;
    return Scaffold(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GhostButton(
                  density: ButtonDensity.icon,
                  onPressed: onBack,
                  child: const Icon(LucideIcons.chevronLeft, size: 18),
                ),
                StatusDot(sessionStateColor(context, s.state)),
                const Gap(8),
                Expanded(
                  child: Text(
                    s.name,
                    overflow: TextOverflow.ellipsis,
                  ).small().semiBold(),
                ),
                if (acc.hasReading)
                  Text(
                    '5h ${acc.fiveHour.usedPercent.round()}% · 7d ${acc.sevenDay.usedPercent.round()}%',
                  ).xSmall().muted(),
                const Gap(12),
              ],
            ),
            const Divider(),
            Expanded(
              child: s.live && d != null ? _liveTerminal(d) : TerminalView(s),
            ),
            const Divider(),
            if (s.live && d != null)
              LiveInputBar(onSend: (data) => d.input(s.id, data)),
          ],
        ),
      ),
    );
  }

  Widget _liveTerminal(DaemonClient d) {
    final grid = d.grids[session.id];
    Widget terminal(g) => LiveTerminal(
      grid: g,
      onInput: (data) => d.input(session.id, data),
      onResize: (cols, rows) => d.resize(session.id, cols, rows),
    );
    return grid == null
        ? terminal(null)
        : ListenableBuilder(
            listenable: grid,
            builder: (context, _) => terminal(grid.state),
          );
  }
}

/// A plan on the phone: the plan view, compact, while it is being reviewed;
/// then the cards, with PR links and retry.
class _ProjectScreen extends StatelessWidget {
  const _ProjectScreen(this.store, this.project, {required this.onBack});

  final HarnessStore store;
  final Project project;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final plan = p.plan;
    return Scaffold(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                GhostButton(
                  density: ButtonDensity.icon,
                  onPressed: onBack,
                  child: const Icon(LucideIcons.chevronLeft, size: 18),
                ),
                Expanded(
                  child: Text(
                    p.name,
                    overflow: TextOverflow.ellipsis,
                  ).small().semiBold(),
                ),
                const Gap(12),
              ],
            ),
            const Divider(),
            Expanded(
              child: plan != null && p.isPlanning
                  // Read, comment, approve and start from the phone.
                  ? PlanView(store, p, compact: true)
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final c in p.cards)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: OutlinedContainer(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('#${c.number}').xSmall().muted(),
                                      const Gap(6),
                                      Expanded(
                                        child: Text(c.title).small().semiBold(),
                                      ),
                                      OutlineBadge(
                                        child: Text(
                                          _column(context.l10n, p.columnOf(c)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (c.halt != null) ...[
                                    const Gap(4),
                                    Text(c.halt!).xSmall().muted(),
                                    const Gap(4),
                                    OutlineButton(
                                      size: ButtonSize.small,
                                      onPressed: () => store.retryCard(p, c),
                                      child: Text(context.l10n.devRetry),
                                    ),
                                  ],
                                  if (c.prUrl != null) ...[
                                    const Gap(4),
                                    GhostButton(
                                      size: ButtonSize.small,
                                      leading: const Icon(
                                        LucideIcons.gitPullRequest,
                                        size: 12,
                                      ),
                                      onPressed: () =>
                                          launchUrl(Uri.parse(c.prUrl!)),
                                      child: Text('PR #${c.pr}'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _column(AppLocalizations l, KanbanColumn c) => switch (c) {
    KanbanColumn.blocked => l.devColumnBlocked,
    KanbanColumn.ready => l.devColumnReady,
    KanbanColumn.running => l.devColumnRunning,
    KanbanColumn.review => l.devColumnReview,
    KanbanColumn.done => l.devColumnDone,
  };
}
