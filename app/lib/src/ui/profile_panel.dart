import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../model.dart';

/// Skills, MCPs and envs of the focused session, picked from the global
/// catalog. Applying restarts the process with `--resume`.
class ProfilePanel extends StatelessWidget {
  const ProfilePanel(this.store, {super.key});

  final HarnessStore store;

  @override
  Widget build(BuildContext context) {
    final s = store.focusedSession;
    if (s == null) {
      return Center(
        child: Text(context.l10n.shellSelectSession).small().muted(),
      );
    }
    final restarting = s.state == SessionState.starting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                context.l10n.shellSessionProfile,
              ).xSmall().semiBold().muted(),
              Text(s.name).large().semiBold(),
              Text(
                '${store.account(s.accountId).email} · ${s.model}',
              ).xSmall().muted(),
              const Gap(16),
              for (final kind in CatalogKind.values) ...[
                _Section(kind, s, store, enabled: !restarting),
                const Gap(12),
              ],
              if (s.live && store.daemon != null)
                _Connectors(s, store, enabled: !restarting),
            ],
          ),
        ),
        if (s.hasPendingChanges || restarting) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: restarting
                ? Text(context.l10n.shellRestartingWithResume).small().muted()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(context.l10n.shellApplyHint).xSmall().muted(),
                      const Gap(8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlineButton(
                              onPressed: () => store.discardDraft(s),
                              child: Text(context.l10n.shellDiscard),
                            ),
                          ),
                          const Gap(8),
                          Expanded(
                            child: PrimaryButton(
                              leading: const Icon(
                                LucideIcons.refreshCw,
                                size: 14,
                              ),
                              onPressed: () => store.applyDraft(s),
                              child: Text(context.l10n.shellApply),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.kind, this.session, this.store, {required this.enabled});

  final CatalogKind kind;
  final Session session;
  final HarnessStore store;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final items = store.profileItems.where((i) => i.kind == kind);
    final title = switch (kind) {
      CatalogKind.skill => 'Skills',
      CatalogKind.mcp => 'MCPs',
      CatalogKind.env => 'Envs',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase()).xSmall().semiBold().muted(),
        const Gap(6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Checkbox(
              enabled: enabled,
              state: session.draftItems.contains(item.id)
                  ? CheckboxState.checked
                  : CheckboxState.unchecked,
              onChanged: (_) => store.toggleItem(session, item.id),
              trailing: Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name).small().medium(),
                    Text(item.description).xSmall().muted(),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The account's claude.ai connectors (Gmail, Drive, Slack…), switched on
/// per session like the rest. Listing them is slow: Claude Code checks each.
class _Connectors extends StatefulWidget {
  const _Connectors(this.session, this.store, {required this.enabled});

  final Session session;
  final HarnessStore store;
  final bool enabled;

  @override
  State<_Connectors> createState() => _ConnectorsState();
}

class _ConnectorsState extends State<_Connectors> {
  @override
  void initState() {
    super.initState();
    final d = widget.store.daemon!;
    if (!d.connectors.containsKey(widget.session.accountId)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => d.listConnectors(widget.session.accountId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final d = widget.store.daemon!;
    final s = widget.session;
    final listed = d.connectors[s.accountId];
    final loading = d.connectorsLoading.contains(s.accountId);
    // Ones the session has on stay visible before the list arrives.
    final items = [
      ...?listed,
      for (final id in s.draftItems.union(s.appliedItems))
        if (id.startsWith('connector:') &&
            !(listed ?? const []).any(
              (c) => HarnessStore.connectorItem(c['url'] as String) == id,
            ))
          {
            'name': id.substring('connector:'.length),
            'url': id.substring('connector:'.length),
            'status': '',
          },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.shellConnectorsTitle.toUpperCase(),
              ).xSmall().semiBold().muted(),
            ),
            GhostButton(
              density: ButtonDensity.icon,
              size: ButtonSize.small,
              onPressed: loading ? null : () => d.listConnectors(s.accountId),
              child: const Icon(LucideIcons.refreshCw, size: 12),
            ),
          ],
        ),
        Text(l10n.shellConnectorsHint).xSmall().muted(),
        const Gap(6),
        if (loading && listed == null)
          Text(l10n.shellConnectorsLoading).xSmall().muted()
        else if (items.isEmpty)
          Text(l10n.shellConnectorsNone).xSmall().muted(),
        for (final c in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Checkbox(
              enabled: widget.enabled,
              state:
                  s.draftItems.contains(
                    HarnessStore.connectorItem(c['url'] as String),
                  )
                  ? CheckboxState.checked
                  : CheckboxState.unchecked,
              onChanged: (_) => widget.store.toggleItem(
                s,
                HarnessStore.connectorItem(c['url'] as String),
              ),
              trailing: Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['name'] as String).small().medium(),
                    if (c['status'] == 'needs_auth')
                      Text(l10n.shellConnectorNeedsAuth).xSmall().muted()
                    else if (c['status'] == 'failed')
                      Text(l10n.shellConnectorFailed).xSmall().muted(),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
