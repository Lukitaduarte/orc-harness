import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
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
                  const Text('Catálogo').large().semiBold(),
                  const Text(
                    'Configure uma vez; cada sessão liga o que precisa no painel de perfil.',
                  ).xSmall().muted(),
                ],
              ),
            ),
            PrimaryButton(
              leading: const Icon(LucideIcons.plus, size: 14),
              onPressed: () => _showAddDialog(context, store),
              child: const Text('Adicionar'),
            ),
          ],
        ),
        const Gap(16),
        for (final kind in CatalogKind.values) ...[
          Text(_kindTitle(kind).toUpperCase()).xSmall().semiBold().muted(),
          const Gap(8),
          for (final item in store.catalog.where((i) => i.kind == kind))
            _ItemRow(store, item),
          const Gap(16),
        ],
        Row(
          children: [
            const Expanded(
              child: Text('TEMPLATES DE PLAN MODE'),
            ).xSmall().semiBold().muted(),
            GhostButton(
              size: ButtonSize.small,
              leading: const Icon(LucideIcons.plus, size: 12),
              onPressed: () => showTemplateEditor(context, store),
              child: const Text('Novo template'),
            ),
          ],
        ),
        const Gap(4),
        const Text(
          'Markdown com as seções de cada tipo de trabalho e a instrução de cada uma. '
          'Escolhido no "Novo plano".',
        ).xSmall().muted(),
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
            Text('$sections seções').xSmall().muted(),
            const Gap(12),
            OutlineButton(
              size: ButtonSize.small,
              onPressed: () =>
                  showTemplateEditor(context, store, template: template),
              child: const Text('Editar markdown'),
            ),
          ],
        ),
      ),
    );
  }
}

String _kindTitle(CatalogKind k) => switch (k) {
  CatalogKind.skill => 'Skills',
  CatalogKind.mcp => 'MCPs',
  CatalogKind.env => 'Envs',
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
                  ? 'sem uso'
                  : 'em $using sess${using > 1 ? 'ões' : 'ão'}',
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
    final status = switch (check) {
      McpCheck.untested => null,
      McpCheck.testing => const Text('testando…').xSmall().muted(),
      McpCheck.ok => const Text(
        'conectado · 12 tools',
      ).xSmall().medium(color: Colors.emerald),
      McpCheck.failed => Text(
        'falhou: token expirado',
      ).xSmall().medium(color: scheme.destructive),
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
          child: const Text('Testar conexão'),
        ),
      ],
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
      CatalogKind.skill => 'Pasta da skill',
      CatalogKind.mcp => 'Comando ou URL',
      CatalogKind.env => 'Valor (guardado no Keychain)',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Adicionar ao catálogo').large().semiBold(),
        const Gap(16),
        Row(
          children: [
            for (final k in CatalogKind.values) ...[
              Expanded(
                child: k == _kind
                    ? PrimaryButton(
                        onPressed: () {},
                        child: Text(_kindTitle(k)),
                      )
                    : OutlineButton(
                        onPressed: () => setState(() => _kind = k),
                        child: Text(_kindTitle(k)),
                      ),
              ),
              if (k != CatalogKind.values.last) const Gap(8),
            ],
          ],
        ),
        const Gap(16),
        const Text('Nome').small().medium(),
        const Gap(6),
        TextField(controller: _name, autofocus: true),
        const Gap(12),
        const Text('Descrição').small().medium(),
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
              child: const Text('Cancelar'),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: _name.text.trim().isEmpty ? null : _save,
              child: const Text('Adicionar'),
            ),
          ],
        ),
      ],
    );
  }
}
