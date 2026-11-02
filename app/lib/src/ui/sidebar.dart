import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../model.dart';
import 'format.dart';

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
          const Spacer(),
          GhostButton(
            density: ButtonDensity.icon,
            onPressed: () {},
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
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(store.workspace.name).large().semiBold(),
        Text(
          '${accounts.length} contas · ${sessions.length} sessões',
        ).xSmall().muted(),
        const Gap(16),
        const _SectionLabel('Contas'),
        for (final a in accounts) _AccountCard(a, store.now),
        const Gap(8),
        const _SectionLabel('Sessões'),
        for (final s in sessions)
          _SessionRow(
            s,
            selected: store.openProjectId == null && s.id == focused?.id,
            onTap: () => store.showSession(s.id),
          ),
        GhostButton(
          alignment: Alignment.centerLeft,
          leading: const Icon(LucideIcons.plus, size: 16),
          onPressed: store.newSession,
          child: const Text('Nova sessão').small(),
        ),
        const Gap(16),
        const _SectionLabel('Projetos'),
        for (final p in store.workspaceProjects)
          _ProjectRow(
            p,
            selected: p.id == store.openProjectId,
            onTap: () => store.openProjectView(p.id),
          ),
        if (store.workspaceProjects.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('Nenhum projeto ainda'),
          ).xSmall().muted(),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text.toUpperCase()).xSmall().semiBold().muted(),
  );
}

class _AccountCard extends StatelessWidget {
  const _AccountCard(this.account, this.now);

  final Account account;
  final DateTime now;

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    account.email,
                    overflow: TextOverflow.ellipsis,
                  ).small().medium(),
                ),
                OutlineBadge(child: Text(account.plan)),
              ],
            ),
            const Gap(10),
            QuotaMeter('5h', account.fiveHour, now),
            const Gap(8),
            QuotaMeter('7d', account.sevenDay, now),
            // Idle accounts keep their last reading instead of dropping to zero.
            if (age.inMinutes >= 5) ...[
              const Gap(6),
              Text('atualizado há ${formatDuration(age)}').xSmall().muted(),
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
                  'reset em ${formatDuration(window.resetsAt.difference(now))}',
                ).xSmall().muted()
              : Text(
                  'nesse ritmo, esgota em ~${formatDuration(exhaust)}',
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
            Text(
              '${project.doneCount}/${project.cards.length}',
            ).xSmall().muted(),
          ],
        ),
      ),
    ),
  );
}
