import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
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
      return Center(child: Text('Selecione uma sessão').small().muted());
    }
    final restarting = s.state == SessionState.starting;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Text('Perfil da sessão').xSmall().semiBold().muted(),
              Text(s.name).large().semiBold(),
              Text(
                '${store.account(s.accountId).email} · ${s.model}',
              ).xSmall().muted(),
              const Gap(16),
              for (final kind in CatalogKind.values) ...[
                _Section(kind, s, store, enabled: !restarting),
                const Gap(12),
              ],
            ],
          ),
        ),
        if (s.hasPendingChanges || restarting) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: restarting
                ? const Text('Reiniciando com --resume…').small().muted()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Aplicar reinicia a sessão com --resume. O contexto é mantido.',
                      ).xSmall().muted(),
                      const Gap(8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlineButton(
                              onPressed: () => store.discardDraft(s),
                              child: const Text('Descartar'),
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
                              child: const Text('Aplicar'),
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
