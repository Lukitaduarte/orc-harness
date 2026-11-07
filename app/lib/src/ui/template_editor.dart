import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../model.dart';
import '../plan_markdown.dart';
import '../plan_templates.dart';

/// Edits a plan mode template's markdown, with a live reading of what the
/// harness understood (sections, instructions, diagrams, loops).
Future<void> showTemplateEditor(
  BuildContext context,
  HarnessStore store, {
  PlanTemplate? template,
}) {
  return showOverlay<void>(
    context,
    DialogConfiguration<void>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints.tightFor(width: 980, height: 720),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              padding: const EdgeInsets.all(20),
              child: _Editor(store, template),
            ),
          ),
        );
      },
    ),
  ).future;
}

class _Editor extends StatefulWidget {
  const _Editor(this.store, this.template);

  final HarnessStore store;
  final PlanTemplate? template;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late final _description = TextEditingController(
    text: widget.template?.description ?? '',
  );
  late final _markdown = TextEditingController(
    text: widget.template?.markdown ?? blankTemplate,
  );

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    _markdown.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _markdown]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final t = widget.template;
    if (t == null) {
      widget.store.addTemplate(
        _name.text.trim(),
        _description.text.trim(),
        _markdown.text,
      );
    } else {
      widget.store.updateTemplate(
        t,
        name: _name.text.trim(),
        description: _description.text.trim(),
        markdown: _markdown.text,
      );
    }
    closeOverlay(context);
  }

  @override
  Widget build(BuildContext context) {
    final mono = Theme.of(context).typography.mono.copyWith(fontSize: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.template == null
              ? context.l10n.toolsNewPlanTemplate
              : context.l10n.toolsEditTemplate,
        ).large().semiBold(),
        const Gap(12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _name,
                placeholder: Text(context.l10n.toolsTemplateNameHint),
              ),
            ),
            const Gap(8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _description,
                placeholder: Text(context.l10n.toolsTemplateDescriptionHint),
              ),
            ),
          ],
        ),
        const Gap(12),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _markdown,
                  expands: true,
                  maxLines: null,
                  style: mono,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
              const Gap(12),
              SizedBox(width: 300, child: _Reading(_markdown.text)),
            ],
          ),
        ),
        const Gap(12),
        Row(
          children: [
            if (widget.template != null)
              GhostButton(
                onPressed: () {
                  widget.store.removeTemplate(widget.template!);
                  closeOverlay(context);
                },
                child: Text(context.l10n.toolsDeleteTemplate).muted(),
              ),
            const Spacer(),
            OutlineButton(
              onPressed: () => closeOverlay(context),
              child: Text(context.l10n.toolsCancel),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: _name.text.trim().isEmpty ? null : _save,
              child: Text(context.l10n.toolsSave),
            ),
          ],
        ),
      ],
    );
  }
}

/// What the parser understood from the markdown, updated as you type.
class _Reading extends StatelessWidget {
  const _Reading(this.markdown);

  final String markdown;

  @override
  Widget build(BuildContext context) {
    Plan? plan;
    String? error;
    try {
      plan = parsePlanMarkdown(markdown).plan;
    } catch (e) {
      error = '$e';
    }
    return OutlinedContainer(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Text(context.l10n.toolsHarnessUnderstood).xSmall().semiBold().muted(),
          const Gap(8),
          if (error != null)
            Text(
              context.l10n.toolsReadError(error),
            ).xSmall().medium(color: Theme.of(context).colorScheme.destructive)
          else ...[
            Text(
              context.l10n.toolsSectionsAndLoops(
                plan!.sections.length,
                plan.proposedCards.length,
              ),
            ).small().semiBold(),
            const Gap(8),
            for (final s in plan.sections) ...[
              Row(
                children: [
                  Expanded(child: Text(s.title).small().medium()),
                  Text('#${s.id}').mono().xSmall().muted(),
                ],
              ),
              Text(_kinds(context, s)).xSmall().muted(),
              if (s.instruction.isNotEmpty)
                Text(
                  context.l10n.toolsInstruction(s.instruction),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ).xSmall().muted(),
              const Gap(8),
            ],
          ],
        ],
      ),
    );
  }

  static String _kinds(BuildContext context, PlanSection s) {
    final t = context.l10n;
    final names = s.blocks.map(
      (b) => switch (b) {
        TextBlock() => t.toolsBlockText,
        BulletsBlock() => t.toolsBlockList,
        TableBlock() => t.toolsBlockTable,
        CodeBlock() => t.toolsBlockCode,
        FlowchartBlock() => t.toolsBlockFlowchart,
        SequenceBlock() => t.toolsBlockSequence,
        LoopsBlock() => t.toolsBlockLoops,
      },
    );
    return names.isEmpty ? t.toolsSectionEmpty : names.join(' · ');
  }
}
