import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../live/daemon_client.dart';
import '../model.dart';
import 'template_editor.dart';

/// Global catalog of skills, MCPs and envs: configured once here, then
/// switched on per session in the profile panel.
class CatalogView extends StatefulWidget {
  const CatalogView(this.store, {super.key});

  final HarnessStore store;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  String _query = '';
  final _all = <CatalogKind>{};

  /// Per kind, until "show all" (hundreds of skills after an import).
  static const cap = 30;

  HarnessStore get store => widget.store;

  List<CatalogItem> _items(CatalogKind kind) {
    final q = _query.toLowerCase();
    return store.catalog
        .where((i) => i.kind == kind)
        .where(
          (i) =>
              q.isEmpty ||
              '${i.name} ${i.description} ${i.detail}'.toLowerCase().contains(
                q,
              ),
        )
        .toList();
  }

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
                onPressed: () => _showImportDialog(
                  context,
                  store.daemon!,
                  store.workspaceId,
                ),
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
        const Gap(12),
        TextField(
          placeholder: Text(context.l10n.toolsCatalogSearch),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        const Gap(16),
        for (final kind in CatalogKind.values) ...[
          Text(
            '${_kindTitle(context, kind).toUpperCase()} · ${_items(kind).length}',
          ).xSmall().semiBold().muted(),
          const Gap(8),
          for (final item in _items(
            kind,
          ).take(_all.contains(kind) ? 100000 : cap))
            _ItemRow(store, item),
          if (!_all.contains(kind) && _items(kind).length > cap)
            GhostButton(
              size: ButtonSize.small,
              onPressed: () => setState(() => _all.add(kind)),
              child: Text(context.l10n.toolsShowAll(_items(kind).length)),
            ),
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
                      if (item.workspaceId != null) ...[
                        const Gap(6),
                        SecondaryBadge(
                          child: Text(
                            store.workspaces
                                    .where((w) => w.id == item.workspaceId)
                                    .map((w) => w.name)
                                    .firstOrNull ??
                                item.workspaceId!,
                          ),
                        ),
                      ],
                      const Gap(8),
                      Flexible(
                        child: Text(
                          item.description,
                          overflow: TextOverflow.ellipsis,
                        ).xSmall().muted(),
                      ),
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

Future<void> _showImportDialog(
  BuildContext context,
  DaemonClient daemon,
  String workspace,
) {
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
              child: McpImportForm(daemon, workspace: workspace),
            ),
          ),
        );
      },
    ),
  ).future;
}

/// MCP servers and skills already on this Mac (Claude Code setups, other
/// tools, projects, plugins), to pick into the catalog. Grouped by where
/// they were found, with a search. Secret values never come here: the
/// daemon moves them to the Keychain and shows only their names.
class McpImportForm extends StatefulWidget {
  const McpImportForm(this.daemon, {super.key, this.workspace});

  final DaemonClient daemon;

  /// Envs the imported servers need belong to it.
  final String? workspace;

  @override
  State<McpImportForm> createState() => _McpImportFormState();
}

class _McpImportFormState extends State<McpImportForm> {
  Set<String>? _picked;
  final _open = <String>{};
  String _query = '';

  bool _matches(Map<String, dynamic> i) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return '${i['name']} ${i['label']} ${i['description'] ?? ''}'
        .toLowerCase()
        .contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: widget.daemon,
      builder: (context, _) {
        final items = widget.daemon.mcpImports;
        // New MCP servers start picked; skills (often hundreds) don't.
        final picked = _picked ??= items == null
            ? null
            : {
                for (final i in items)
                  if (i['in_catalog'] != true && i['kind'] != 'skill')
                    i['key'] as String,
              };
        final shown = (items ?? const <Map<String, dynamic>>[])
            .where(_matches)
            .toList();
        // kind → source → items, in the order found.
        final groups = <String, Map<String, List<Map<String, dynamic>>>>{};
        for (final i in shown) {
          groups
              .putIfAbsent(i['kind'] as String? ?? 'mcp', () => {})
              .putIfAbsent(i['label'] as String, () => [])
              .add(i);
        }
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
            else ...[
              TextField(
                placeholder: Text(l10n.toolsImportSearch),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const Gap(8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final kind in ['mcp', 'skill'])
                      if (groups[kind] != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Text(
                            (kind == 'mcp' ? 'MCPs' : 'Skills').toUpperCase(),
                          ).xSmall().semiBold().muted(),
                        ),
                        for (final MapEntry(key: label, value: list)
                            in groups[kind]!.entries)
                          ..._group(kind, label, list, picked!),
                      ],
                  ],
                ),
              ),
            ],
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
                          widget.daemon.importMcps(
                            picked.toList(),
                            workspace: widget.workspace,
                          );
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

  /// A source: a header with its count and a pick-all box; open shows
  /// its items (a search opens every group).
  List<Widget> _group(
    String kind,
    String label,
    List<Map<String, dynamic>> list,
    Set<String> picked,
  ) {
    final id = '$kind|$label';
    final open = _query.isNotEmpty || _open.contains(id);
    final keys = [for (final i in list) i['key'] as String];
    final on = keys.where(picked.contains).length;
    return [
      Row(
        children: [
          Checkbox(
            state: on == 0
                ? CheckboxState.unchecked
                : on == keys.length
                ? CheckboxState.checked
                : CheckboxState.indeterminate,
            tristate: true,
            onChanged: (_) => setState(() {
              on == keys.length ? picked.removeAll(keys) : picked.addAll(keys);
            }),
          ),
          const Gap(4),
          Expanded(
            child: GhostButton(
              alignment: Alignment.centerLeft,
              density: ButtonDensity.compact,
              onPressed: () => setState(() {
                if (!_open.remove(id)) _open.add(id);
              }),
              trailing: Icon(
                open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                size: 12,
              ),
              child: Text(
                '$label  ·  ${list.length}',
                overflow: TextOverflow.ellipsis,
              ).small().medium(),
            ),
          ),
        ],
      ),
      if (open)
        for (final i in list)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: _row(i, picked),
          ),
    ];
  }

  Widget _row(Map<String, dynamic> i, Set<String> picked) {
    final l10n = context.l10n;
    final key = i['key'] as String;
    final skill = i['kind'] == 'skill';
    final mcp = i['mcp'] as Map<String, dynamic>?;
    final secrets = (i['secrets'] as List? ?? const []).cast<String>();
    final detail = skill
        ? (i['description'] as String? ?? '')
        : mcp?['url'] as String? ??
              [
                mcp?['command'],
                ...(mcp?['args'] as List? ?? const []),
              ].join(' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
                    Flexible(
                      child: Text(
                        i['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ).small().semiBold(),
                    ),
                    if (i['in_catalog'] == true) ...[
                      const Gap(6),
                      Text(
                        skill
                            ? l10n.toolsImportInCatalog
                            : l10n.toolsImportReplaces,
                      ).xSmall().muted(),
                    ],
                  ],
                ),
                if (detail.isNotEmpty)
                  skill
                      ? Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ).xSmall().muted()
                      : Text(
                          detail,
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

  /// An env only for the workspace you are in (its own value).
  bool _onlyHere = true;

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
      onlyThisWorkspace: isEnv && _onlyHere,
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
        if (_kind == CatalogKind.env && widget.store.isLive) ...[
          const Gap(12),
          Checkbox(
            state: _onlyHere ? CheckboxState.checked : CheckboxState.unchecked,
            onChanged: (v) =>
                setState(() => _onlyHere = v == CheckboxState.checked),
            trailing: Expanded(
              child: Text(
                context.l10n.toolsEnvOnlyHere(widget.store.workspace.name),
              ).small(),
            ),
          ),
        ],
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
