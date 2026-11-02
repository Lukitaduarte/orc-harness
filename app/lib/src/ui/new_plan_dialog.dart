import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../model.dart';

/// "Novo plano": from a plan mode template (Claude reads the sources and
/// fills the template's sections), or by pasting a plan already written in
/// markdown.
Future<void> showNewPlanDialog(
  BuildContext context,
  HarnessStore store, {
  bool importing = false,
}) {
  return showOverlay<void>(
    context,
    DialogConfiguration<void>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              padding: const EdgeInsets.all(20),
              child: _NewPlanForm(store, importing: importing),
            ),
          ),
        );
      },
    ),
  ).future;
}

class _NewPlanForm extends StatefulWidget {
  const _NewPlanForm(this.store, {required this.importing});

  final HarnessStore store;
  final bool importing;

  @override
  State<_NewPlanForm> createState() => _NewPlanFormState();
}

class _NewPlanFormState extends State<_NewPlanForm> {
  late bool _importing = widget.importing;
  late PlanTemplate _template = widget.store.planTemplates.first;
  final _name = TextEditingController();
  final _links = TextEditingController();
  final _description = TextEditingController();
  final _markdown = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _markdown.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_name, _links, _description, _markdown]) {
      c.dispose();
    }
    super.dispose();
  }

  void _create() {
    if (_importing) {
      widget.store.importPlan(_markdown.text);
    } else {
      final links = _links.text
          .split(RegExp(r'\s+'))
          .where((l) => l.startsWith('http'))
          .toList();
      widget.store.createPlan(
        _name.text.trim(),
        _description.text.trim(),
        links,
        _template,
      );
    }
    closeOverlay(context);
  }

  bool get _ready => _importing
      ? _markdown.text.contains('## ')
      : _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Novo plano').large().semiBold(),
        const Gap(12),
        Row(
          children: [
            Expanded(child: _modeButton('A partir de um template', false)),
            const Gap(8),
            Expanded(child: _modeButton('Colar markdown', true)),
          ],
        ),
        const Gap(16),
        if (_importing) ..._importFields() else ..._templateFields(),
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
              leading: const Icon(LucideIcons.sparkles, size: 14),
              onPressed: _ready ? _create : null,
              child: Text(_importing ? 'Importar plano' : 'Criar plano'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _modeButton(String label, bool importing) => importing == _importing
      ? SecondaryButton(onPressed: () {}, child: Text(label))
      : GhostButton(
          onPressed: () => setState(() => _importing = importing),
          child: Text(label),
        );

  List<Widget> _templateFields() => [
    const Text('Template').small().medium(),
    const Gap(6),
    for (final t in widget.store.planTemplates)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          onTap: () => setState(() => _template = t),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: OutlinedContainer(
              padding: const EdgeInsets.all(10),
              borderColor: t == _template
                  ? Theme.of(context).colorScheme.primary
                  : null,
              borderWidth: t == _template ? 1.5 : 1,
              child: Row(
                children: [
                  Icon(
                    t == _template ? LucideIcons.circleDot : LucideIcons.circle,
                    size: 14,
                  ),
                  const Gap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name).small().semiBold(),
                        Text(t.description).xSmall().muted(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    const Gap(10),
    const Text('Nome da feature').small().medium(),
    const Gap(6),
    TextField(controller: _name, autofocus: true),
    const Gap(12),
    const Text(
      'Fontes (Jira, Confluence, Figma), uma por linha',
    ).small().medium(),
    const Gap(6),
    TextField(
      controller: _links,
      minLines: 2,
      maxLines: 5,
      placeholder: const Text('https://empresa.atlassian.net/browse/MOB-123'),
    ),
    const Gap(12),
    const Text('O que construir').small().medium(),
    const Gap(6),
    TextField(controller: _description, minLines: 2, maxLines: 4),
  ];

  List<Widget> _importFields() => [
    const Text(
      'Qualquer markdown no formato de plano: cada ## vira uma seção aprovável, '
      'tabelas e listas viram widgets, ```mermaid vira diagrama e ```loops '
      'define a execução.',
    ).xSmall().muted(),
    const Gap(10),
    TextField(
      controller: _markdown,
      autofocus: true,
      minLines: 14,
      maxLines: 20,
      style: Theme.of(context).typography.mono.copyWith(fontSize: 12),
      placeholder: const Text('# Nome do plano\n\n## Fontes\n…'),
    ),
  ];
}
