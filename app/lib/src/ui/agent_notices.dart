import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';

/// Above the panes: env values agents ask to store (your call) and the
/// latest messages between sessions.
class AgentNotices extends StatelessWidget {
  const AgentNotices(this.store, {super.key});

  final HarnessStore store;

  @override
  Widget build(BuildContext context) {
    final d = store.daemon;
    if (d == null ||
        (d.envRequests.isEmpty && d.messages.isEmpty && d.approvals.isEmpty)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    String name(String id) {
      final s = d.sessions.where((x) => x.id == id).firstOrNull;
      return s == null ? id : '${s.branch ?? s.cwd.split('/').last} ($id)';
    }

    return Container(
      color: scheme.muted.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (id, session, action) in d.approvals)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.shieldAlert,
                    size: 14,
                    color: scheme.destructive,
                  ),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      l10n.shellApprovalRequest(name(session), action),
                    ).small(),
                  ),
                  OutlineButton(
                    size: ButtonSize.small,
                    onPressed: () => d.resolveApproval(id, false),
                    child: Text(l10n.shellDecline),
                  ),
                  const Gap(6),
                  PrimaryButton(
                    size: ButtonSize.small,
                    onPressed: () => d.resolveApproval(id, true),
                    child: Text(l10n.shellApprove),
                  ),
                ],
              ),
            ),
          for (final (id, session, env) in d.envRequests)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(LucideIcons.keyRound, size: 14),
                  const Gap(8),
                  Expanded(
                    child: Text(
                      l10n.shellEnvRequest(name(session), env),
                    ).small(),
                  ),
                  OutlineButton(
                    size: ButtonSize.small,
                    onPressed: () => d.resolveEnvRequest(id, false),
                    child: Text(l10n.shellDecline),
                  ),
                  const Gap(6),
                  PrimaryButton(
                    size: ButtonSize.small,
                    onPressed: () => d.resolveEnvRequest(id, true),
                    child: Text(l10n.shellApprove),
                  ),
                ],
              ),
            ),
          if (d.messages.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LucideIcons.messagesSquare, size: 14),
                const Gap(8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (from, to, body) in d.messages)
                        Text(
                          '${from == 'harness' ? 'harness' : name(from)} → ${name(to)}: $body',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ).xSmall(),
                    ],
                  ),
                ),
                GhostButton(
                  size: ButtonSize.small,
                  onPressed: d.dismissMessages,
                  child: Text(l10n.shellDismiss),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
