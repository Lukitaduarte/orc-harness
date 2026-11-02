import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';

/// "Novo plano": name, the sources (Jira, Confluence, Figma links) and what
/// to build. The planning session reads the sources and drafts the sections.
Future<void> showNewPlanDialog(BuildContext context, HarnessStore store) {
  return showOverlay<void>(
    context,
    DialogConfiguration<void>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints.tightFor(width: 520),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              padding: const EdgeInsets.all(20),
              child: _NewPlanForm(store),
            ),
          ),
        );
      },
    ),
  ).future;
}

class _NewPlanForm extends StatefulWidget {
  const _NewPlanForm(this.store);

  final HarnessStore store;

  @override
  State<_NewPlanForm> createState() => _NewPlanFormState();
}

class _NewPlanFormState extends State<_NewPlanForm> {
  final _name = TextEditingController();
  final _links = TextEditingController();
  final _description = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _links.dispose();
    _description.dispose();
    super.dispose();
  }

  void _create() {
    final links = _links.text
        .split(RegExp(r'\s+'))
        .where((l) => l.startsWith('http'))
        .toList();
    widget.store.createPlan(_name.text.trim(), _description.text.trim(), links);
    closeOverlay(context);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Novo plano').large().semiBold(),
      const Text(
        'Claude lê as fontes, responde o checklist e escreve as seções. '
        'Você aprova cada uma antes de executar.',
      ).xSmall().muted(),
      const Gap(16),
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
        minLines: 3,
        maxLines: 6,
        placeholder: const Text('https://empresa.atlassian.net/browse/MOB-123'),
      ),
      const Gap(12),
      const Text('O que construir').small().medium(),
      const Gap(6),
      TextField(controller: _description, minLines: 2, maxLines: 4),
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
            onPressed: _name.text.trim().isEmpty ? null : _create,
            child: const Text('Criar plano'),
          ),
        ],
      ),
    ],
  );
}
