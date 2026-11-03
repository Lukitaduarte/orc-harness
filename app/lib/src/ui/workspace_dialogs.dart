import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../model.dart';

Future<void> _dialog(BuildContext context, Widget child) => showOverlay<void>(
  context,
  DialogConfiguration<void>(
    builder: (context) {
      final theme = Theme.of(context);
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: ModalBackdrop(
          borderRadius: theme.borderRadiusXl,
          child: OutlinedContainer(
            backgroundColor: theme.colorScheme.popover,
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      );
    },
  ),
).future;

/// New workspace ([editing] null) or rename / accounts / delete.
Future<void> showWorkspaceDialog(
  BuildContext context,
  HarnessStore store, {
  Workspace? editing,
}) => _dialog(context, _WorkspaceForm(store, editing));

/// A new Claude Code account in the current workspace.
Future<void> showNewAccountDialog(BuildContext context, HarnessStore store) =>
    _dialog(context, _NewAccount(store));

class _WorkspaceForm extends StatefulWidget {
  const _WorkspaceForm(this.store, this.editing);

  final HarnessStore store;
  final Workspace? editing;

  @override
  State<_WorkspaceForm> createState() => _WorkspaceFormState();
}

class _WorkspaceFormState extends State<_WorkspaceForm> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late final Set<String> _accounts = {
    if (widget.editing case final w?) ...widget.store.liveAccountsOf(w.id),
  };

  late String _memory = widget.editing == null
      ? 'orc'
      : widget.store.memoryOf(widget.editing!.id);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
    if (widget.editing case final w?) widget.store.daemon?.listMemory(w.id);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Widget _choice(String value, String label) => value == _memory
      ? SecondaryButton(
          size: ButtonSize.small,
          onPressed: () {},
          child: Text(label),
        )
      : GhostButton(
          size: ButtonSize.small,
          onPressed: () => setState(() => _memory = value),
          child: Text(label),
        );

  /// Which memory its sessions share, and what the harness's holds.
  List<Widget> _memorySection(HarnessStore store, Workspace? editing) {
    final d = store.daemon!;
    final mcps = d.catalog.where((e) => e['kind'] == 'mcp');
    final entries = editing == null
        ? const []
        : d.memory[editing.id] ?? const [];
    return [
      const Gap(14),
      const Text('Memória das sessões').small().medium(),
      const Text(
        'O que os agentes guardam (decisões, preferências, fatos dos projetos) '
        'e as outras sessões do workspace encontram.',
      ).xSmall().muted(),
      const Gap(6),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _choice('orc', 'Do harness'),
          for (final m in mcps) _choice(m['id'] as String, m['name'] as String),
          _choice('off', 'Desligada'),
        ],
      ),
      if (_memory == 'orc' && entries.isNotEmpty) ...[
        const Gap(8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in entries.reversed)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${e['text']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ).xSmall(),
                    ),
                    GhostButton(
                      density: ButtonDensity.icon,
                      size: ButtonSize.small,
                      onPressed: () =>
                          d.forgetMemory(editing!.id, e['id'] as String),
                      child: const Icon(LucideIcons.trash2, size: 12),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final editing = widget.editing;
    final all = store.accounts.where((a) => a.live).toList();
    final canDelete = editing != null && store.liveWorkspaces.length > 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          editing == null ? 'Novo workspace' : 'Workspace',
        ).large().semiBold(),
        const Text(
          'Um workspace junta contas, sessões, repositórios, planos e um '
          'navegador com logins próprios (ex.: Trabalho, Pessoal).',
        ).xSmall().muted(),
        const Gap(16),
        const Text('Nome').small().medium(),
        const Gap(6),
        TextField(controller: _name, autofocus: true),
        if (all.isNotEmpty) ...[
          const Gap(14),
          const Text('Contas neste workspace').small().medium(),
          const Text(
            'Uma conta fica em um workspace só; marcar aqui a tira do outro.',
          ).xSmall().muted(),
          const Gap(6),
          for (final a in all)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Checkbox(
                state: _accounts.contains(a.id)
                    ? CheckboxState.checked
                    : CheckboxState.unchecked,
                onChanged: (v) => setState(
                  () => v == CheckboxState.checked
                      ? _accounts.add(a.id)
                      : _accounts.remove(a.id),
                ),
                trailing: Text(
                  a.workspaceId == editing?.id || a.workspaceId == ''
                      ? a.email
                      : '${a.email} (em ${store.workspaces.where((w) => w.id == a.workspaceId).map((w) => w.name).firstOrNull ?? a.workspaceId})',
                ).small(),
              ),
            ),
        ],
        // Entries arrive from the daemon after the dialog opens.
        ListenableBuilder(
          listenable: store.daemon!,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _memorySection(store, editing),
          ),
        ),
        const Gap(20),
        Row(
          children: [
            if (canDelete)
              DestructiveButton(
                onPressed: () {
                  store.deleteWorkspace(editing.id);
                  closeOverlay(context);
                },
                child: const Text('Excluir'),
              ),
            const Spacer(),
            OutlineButton(
              onPressed: () => closeOverlay(context),
              child: const Text('Cancelar'),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: _name.text.trim().isEmpty
                  ? null
                  : () {
                      store.saveWorkspace(
                        _name.text,
                        _accounts.toList(),
                        id: editing?.id,
                        memory: _memory,
                      );
                      closeOverlay(context);
                    },
              child: Text(editing == null ? 'Criar' : 'Salvar'),
            ),
          ],
        ),
      ],
    );
  }
}

class _NewAccount extends StatefulWidget {
  const _NewAccount(this.store);

  final HarnessStore store;

  @override
  State<_NewAccount> createState() => _NewAccountState();
}

class _NewAccountState extends State<_NewAccount> {
  final _id = TextEditingController();

  static final _rule = RegExp(r'^[A-Za-z0-9_-]{1,48}$');

  @override
  void initState() {
    super.initState();
    _id.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _id.text.trim();
    final taken = widget.store.accounts.any((a) => a.live && a.id == id);
    final ok = _rule.hasMatch(id) && !taken;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Nova conta').large().semiBold(),
        Text(
          'Uma conta do Claude Code com pasta de configuração própria '
          '(~/.orc/accounts/<nome>) no workspace ${widget.store.workspace.name}. '
          'Abre uma sessão nela: faça o login com /login.',
        ).xSmall().muted(),
        const Gap(16),
        const Text('Nome da conta').small().medium(),
        const Gap(6),
        TextField(
          controller: _id,
          autofocus: true,
          placeholder: const Text('trabalho-2'),
        ),
        if (id.isNotEmpty && !ok) ...[
          const Gap(4),
          Text(
            taken
                ? 'Já existe uma conta com esse nome.'
                : 'Use letras, números, - e _.',
          ).xSmall().muted(),
        ],
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
              onPressed: ok
                  ? () {
                      widget.store.addAccount(id);
                      closeOverlay(context);
                    }
                  : null,
              child: const Text('Criar e fazer login'),
            ),
          ],
        ),
      ],
    );
  }
}
