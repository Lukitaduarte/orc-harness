import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../live/daemon_client.dart';
import '../model.dart';
import 'template_editor.dart';

/// Global catalog of skills, MCPs and envs: configured once here, then
/// switched on per session in the profile panel.
class CatalogView extends StatelessWidget {
  const CatalogView(this.store, {super.key});

  final HarnessStore store;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.toolsCatalogTitle).large().semiBold(),
                  Text(context.l10n.toolsCatalogSubtitle).xSmall().muted(),
                ],
              ),
            ),
            if (store.isLive) ...[
              OutlineButton(
                leading: const Icon(LucideIcons.download, size: 14),
                onPressed: () => _showImportDialog(context, store.daemon!),
                child: Text(context.l10n.toolsImportMcps),
              ),
              const Gap(8),
            ],
            PrimaryButton(
              leading: const Icon(LucideIcons.plus, size: 14),
              onPressed: () => _showAddDialog(context, store),
              child: Text(context.l10n.toolsAdd),
            ),
          ],
        ),
        const Gap(16),
        for (final kind in CatalogKind.values) ...[
          Text(
            _kindTitle(context, kind).toUpperCase(),
          ).xSmall().semiBold().muted(),
          const Gap(8),
          for (final item in store.catalog.where((i) => i.kind == kind))
            _ItemRow(store, item),
          const Gap(16),
        ],
        Row(
          children: [
            Expanded(
              child: Text(context.l10n.toolsPlanTemplatesHeader),
            ).xSmall().semiBold().muted(),
            GhostButton(
              size: ButtonSize.small,
              leading: const Icon(LucideIcons.plus, size: 12),
              onPressed: () => showTemplateEditor(context, store),
              child: Text(context.l10n.toolsNewTemplate),
            ),
          ],
        ),
        const Gap(4),
        Text(context.l10n.toolsPlanTemplatesHelp).xSmall().muted(),
        const Gap(8),
        for (final t in store.planTemplates) _TemplateRow(store, t),
      ],
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow(this.store, this.template);

  final HarnessStore store;
  final PlanTemplate template;

  @override
  Widget build(BuildContext context) {
    final sections = RegExp(
      r'^## ',
      multiLine: true,
    ).allMatches(template.markdown).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedContainer(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(LucideIcons.fileText, size: 16),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name).small().semiBold(),
                  Text(template.description).xSmall().muted(),
                ],
              ),
            ),
            Text(context.l10n.toolsSectionCount(sections)).xSmall().muted(),
            const Gap(12),
            OutlineButton(
              size: ButtonSize.small,
              onPressed: () =>
                  showTemplateEditor(context, store, template: template),
              child: Text(context.l10n.toolsEditMarkdown),
            ),
          ],
        ),
      ),
    );
  }
}

String _kindTitle(BuildContext context, CatalogKind k) => switch (k) {
  CatalogKind.skill => context.l10n.toolsKindSkills,
  CatalogKind.mcp => context.l10n.toolsKindMcps,
  CatalogKind.env => context.l10n.toolsKindEnvs,
};

class _ItemRow extends StatelessWidget {
  const _ItemRow(this.store, this.item);

  final HarnessStore store;
  final CatalogItem item;

  @override
  Widget build(BuildContext context) {
    final using = store.sessions
        .where((s) => s.appliedItems.contains(item.id))
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedContainer(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(item.name).small().semiBold(),
                      const Gap(8),
                      Text(item.description).xSmall().muted(),
                    ],
                  ),
                  if (item.detail.isNotEmpty) ...[
                    const Gap(4),
                    Text(
                      item.detail,
                      overflow: TextOverflow.ellipsis,
                    ).mono().xSmall().muted(),
                  ],
                ],
              ),
            ),
            Text(
              using == 0
                  ? context.l10n.toolsUnused
                  : context.l10n.toolsUsedInSessions(using),
            ).xSmall().muted(),
            const Gap(12),
            if (item.kind == CatalogKind.mcp) ...[
              _mcpStatus(context),
              const Gap(8),
            ],
            GhostButton(
              density: ButtonDensity.icon,
              onPressed: () => store.removeCatalogItem(item),
              child: const Icon(LucideIcons.trash2, size: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mcpStatus(BuildContext context) {
    final check = store.mcpChecks[item.id] ?? McpCheck.untested;
    final scheme = Theme.of(context).colorScheme;
    // Live: the daemon's real result; mock: fixed demo text.
    final result = store.mcpResult(item.id);
    final status = switch (check) {
      McpCheck.untested => null,
      McpCheck.testing => Text(context.l10n.toolsMcpTesting).xSmall().muted(),
      McpCheck.ok => Text(
        context.l10n.toolsMcpConnected('${result?.$2 ?? 12}'),
      ).xSmall().medium(color: Colors.emerald),
      McpCheck.failed => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Text(
          context.l10n.toolsMcpFailed(result?.$3 ?? 'token expirado'),
          overflow: TextOverflow.ellipsis,
        ).xSmall().medium(color: scheme.destructive),
      ),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?status,
        const Gap(8),
        OutlineButton(
          size: ButtonSize.small,
          onPressed: check == McpCheck.testing
              ? null
              : () => store.testMcp(item),
          child: Text(context.l10n.toolsTestConnection),
        ),
      ],
    );
  }
}

Future<void> _showImportDialog(BuildContext context, DaemonClient daemon) {
  daemon.scanMcpImports();
  return showOverlay<void>(
    context,
    DialogConfiguration<void>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints.tightFor(width: 560),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              padding: const EdgeInsets.all(20),
              child: McpImportForm(daemon),
            ),
          ),
        );
      },
    ),
  ).future;
}

/// The MCP servers you already use in Claude Code, to pick into the
/// catalog. Secret values never come here: the daemon moves them to the
/// Keychain and shows only their names.
class McpImportForm extends StatefulWidget {
  const McpImportForm(this.daemon, {super.key});

  final DaemonClient daemon;

  @override
  State<McpImportForm> createState() => _McpImportFormState();
}

class _McpImportFormState extends State<McpImportForm> {
  Set<String>? _picked;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: widget.daemon,
      builder: (context, _) {
        final items = widget.daemon.mcpImports;
        // New ones start picked; ones already in the catalog don't.
        final picked = _picked ??= items == null
            ? null
            : {
                for (final i in items)
                  if (i['in_catalog'] != true) i['key'] as String,
              };
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.toolsImportMcps).large().semiBold(),
            Text(l10n.toolsImportMcpsHint).xSmall().muted(),
            const Gap(12),
            if (items == null)
              Center(child: Text(l10n.devLoading).small().muted())
            else if (items.isEmpty)
              Text(l10n.toolsImportNone).small().muted()
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView(
                  shrinkWrap: true,
                  children: [for (final i in items) _row(i, picked!)],
                ),
              ),
            const Gap(16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlineButton(
                  onPressed: () => closeOverlay(context),
                  child: Text(l10n.shellCancel),
                ),
                const Gap(8),
                PrimaryButton(
                  onPressed: picked == null || picked.isEmpty
                      ? null
                      : () {
                          widget.daemon.importMcps(picked.toList());
                          closeOverlay(context);
                        },
                  child: Text(l10n.toolsImportCount(picked?.length ?? 0)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _row(Map<String, dynamic> i, Set<String> picked) {
    final l10n = context.l10n;
    final key = i['key'] as String;
    final mcp = i['mcp'] as Map<String, dynamic>;
    final secrets = (i['secrets'] as List).cast<String>();
    final runs =
        mcp['url'] as String? ??
        [mcp['command'], ...(mcp['args'] as List? ?? const [])].join(' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            state: picked.contains(key)
                ? CheckboxState.checked
                : CheckboxState.unchecked,
            onChanged: (v) => setState(() {
              v == CheckboxState.checked ? picked.add(key) : picked.remove(key);
            }),
          ),
          const Gap(8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(i['name'] as String).small().semiBold(),
                    const Gap(6),
                    Flexible(
                      child: Text(
                        i['label'] as String,
                        overflow: TextOverflow.ellipsis,
                      ).xSmall().muted(),
                    ),
                    if (i['in_catalog'] == true) ...[
                      const Gap(6),
                      Text(l10n.toolsImportReplaces).xSmall().muted(),
                    ],
                  ],
                ),
                Text(
                  runs,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ).mono().xSmall().muted(),
                if (secrets.isNotEmpty)
                  Text(
                    l10n.toolsImportSecrets(secrets.join(', ')),
                  ).xSmall().muted(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showAddDialog(BuildContext context, HarnessStore store) {
  return showOverlay<void>(
    context,
    DialogConfiguration<void>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints.tightFor(width: 480),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              padding: const EdgeInsets.all(20),
              child: _AddItemForm(store),
            ),
          ),
        );
      },
    ),
  ).future;
}

class _AddItemForm extends StatefulWidget {
  const _AddItemForm(this.store);

  final HarnessStore store;

  @override
  State<_AddItemForm> createState() => _AddItemFormState();
}

class _AddItemFormState extends State<_AddItemForm> {
  CatalogKind _kind = CatalogKind.mcp;
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _detail = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _detail.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    // An env's value goes to the daemon's Keychain; the catalog only keeps
    // where it is.
    final isEnv = _kind == CatalogKind.env;
    final detail = isEnv
        ? 'Keychain do daemon · env/$name'
        : _detail.text.trim();
    widget.store.addCatalogItem(
      _kind,
      name,
      _description.text.trim(),
      detail,
      secretValue: isEnv ? _detail.text : null,
    );
    _detail.clear();
    closeOverlay(context);
  }

  @override
  Widget build(BuildContext context) {
    final detailLabel = switch (_kind) {
      CatalogKind.skill => context.l10n.toolsSkillFolder,
      CatalogKind.mcp => context.l10n.toolsCommandOrUrl,
      CatalogKind.env => context.l10n.toolsEnvValue,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.toolsAddToCatalog).large().semiBold(),
        const Gap(16),
        Row(
          children: [
            for (final k in CatalogKind.values) ...[
              Expanded(
                child: k == _kind
                    ? PrimaryButton(
                        onPressed: () {},
                        child: Text(_kindTitle(context, k)),
                      )
                    : OutlineButton(
                        onPressed: () => setState(() => _kind = k),
                        child: Text(_kindTitle(context, k)),
                      ),
              ),
              if (k != CatalogKind.values.last) const Gap(8),
            ],
          ],
        ),
        const Gap(16),
        Text(context.l10n.toolsName).small().medium(),
        const Gap(6),
        TextField(controller: _name, autofocus: true),
        const Gap(12),
        Text(context.l10n.toolsDescription).small().medium(),
        const Gap(6),
        TextField(controller: _description),
        const Gap(12),
        Text(detailLabel).small().medium(),
        const Gap(6),
        TextField(controller: _detail, obscureText: _kind == CatalogKind.env),
        const Gap(20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlineButton(
              onPressed: () => closeOverlay(context),
              child: Text(context.l10n.toolsCancel),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: _name.text.trim().isEmpty ? null : _save,
              child: Text(context.l10n.toolsAdd),
            ),
          ],
        ),
      ],
    );
  }
}
