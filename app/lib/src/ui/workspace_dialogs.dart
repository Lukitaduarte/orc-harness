import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../live/daemon_client.dart';
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
  late final _budget = TextEditingController(
    text: switch (widget.editing) {
      final w? => widget.store.budgetOf(w.id)?.toStringAsFixed(0) ?? '',
      null => '',
    },
  );
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
    _budget.dispose();
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
    final l10n = context.l10n;
    return [
      const Gap(14),
      Text(l10n.shellSessionMemory).small().medium(),
      Text(l10n.shellSessionMemoryHint).xSmall().muted(),
      const Gap(6),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _choice('orc', l10n.shellMemoryHarness),
          for (final m in mcps) _choice(m['id'] as String, m['name'] as String),
          _choice('off', l10n.shellMemoryOff),
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
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          editing == null ? l10n.shellNewWorkspace : l10n.shellWorkspace,
        ).large().semiBold(),
        Text(l10n.shellWorkspaceHint).xSmall().muted(),
        const Gap(16),
        Text(l10n.shellName).small().medium(),
        const Gap(6),
        TextField(controller: _name, autofocus: true),
        if (all.isNotEmpty) ...[
          const Gap(14),
          Text(l10n.shellWorkspaceAccounts).small().medium(),
          Text(l10n.shellWorkspaceAccountsHint).xSmall().muted(),
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
                      : l10n.shellAccountInWorkspace(
                          a.email,
                          store.workspaces
                                  .where((w) => w.id == a.workspaceId)
                                  .map((w) => w.name)
                                  .firstOrNull ??
                              a.workspaceId,
                        ),
                ).small(),
              ),
            ),
        ],
        const Gap(14),
        Text(l10n.shellMonthlyBudget).small().medium(),
        Text(l10n.shellBudgetHint).xSmall().muted(),
        const Gap(6),
        TextField(
          controller: _budget,
          placeholder: Text(l10n.shellBudgetExample),
        ),
        // Entries arrive from the daemon after the dialog opens.
        ListenableBuilder(
          listenable: store.daemon!,
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _memorySection(store, editing),
          ),
        ),
        const Gap(20),
        // Workspaces live in the daemon: without it nothing can be saved.
        if (store.daemon!.status != LinkStatus.connected) ...[
          Text(l10n.shellNoDaemonToSave).small().muted(),
          const Gap(12),
        ],
        Row(
          children: [
            if (canDelete)
              DestructiveButton(
                onPressed: () {
                  store.deleteWorkspace(editing.id);
                  closeOverlay(context);
                },
                child: Text(l10n.shellDeleteWorkspace),
              ),
            const Spacer(),
            OutlineButton(
              onPressed: () => closeOverlay(context),
              child: Text(l10n.shellCancel),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed:
                  _name.text.trim().isEmpty ||
                      store.daemon!.status != LinkStatus.connected
                  ? null
                  : () {
                      store.saveWorkspace(
                        _name.text,
                        _accounts.toList(),
                        id: editing?.id,
                        memory: _memory,
                        budgetUsd: double.tryParse(
                          _budget.text.trim().replaceAll(',', '.'),
                        ),
                      );
                      closeOverlay(context);
                    },
              child: Text(editing == null ? l10n.shellCreate : l10n.shellSave),
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
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.shellNewAccount).large().semiBold(),
        Text(
          l10n.shellNewAccountBody(widget.store.workspace.name),
        ).xSmall().muted(),
        const Gap(16),
        Text(l10n.shellAccountName).small().medium(),
        const Gap(6),
        TextField(
          controller: _id,
          autofocus: true,
          placeholder: Text(l10n.shellAccountNameExample),
        ),
        if (id.isNotEmpty && !ok) ...[
          const Gap(4),
          Text(
            taken ? l10n.shellAccountTaken : l10n.shellAccountRule,
          ).xSmall().muted(),
        ],
        const Gap(20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlineButton(
              onPressed: () => closeOverlay(context),
              child: Text(l10n.shellCancel),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: ok
                  ? () {
                      widget.store.addAccount(id);
                      closeOverlay(context);
                    }
                  : null,
              child: Text(l10n.shellCreateAndLogin),
            ),
          ],
        ),
      ],
    );
  }
}
