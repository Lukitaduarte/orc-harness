import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';

/// "Este Mac": local repositories, each a source of worktree sessions.
class RepoSection extends StatelessWidget {
  const RepoSection(this.store, {super.key});

  final HarnessStore store;

  @override
  Widget build(BuildContext context) {
    final d = store.daemon!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in store.workspaceRepos)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                const Icon(LucideIcons.gitBranch, size: 14),
                const Gap(8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ).small(),
                      Text('base ${p['base_branch']}').xSmall().muted(),
                    ],
                  ),
                ),
                Tooltip(
                  tooltip: (context) => const TooltipContainer(
                    child: Text('Nova sessão em worktree'),
                  ),
                  child: GhostButton(
                    density: ButtonDensity.icon,
                    size: ButtonSize.small,
                    onPressed: () => _dialog(
                      context,
                      _NewWorktree(
                        store,
                        p['id'] as String,
                        p['name'] as String,
                      ),
                    ),
                    child: const Icon(LucideIcons.plus, size: 14),
                  ),
                ),
              ],
            ),
          ),
        GhostButton(
          alignment: Alignment.centerLeft,
          leading: const Icon(LucideIcons.folderGit2, size: 16),
          onPressed: () => _dialog(context, _AddRepo(store)),
          child: const Text('Adicionar repositório').small(),
        ),
        if (store.workspaceRepos.isNotEmpty &&
            store.workspaceAccounts.isNotEmpty)
          Tooltip(
            tooltip: (context) => const TooltipContainer(
              child: Text(
                'O Claude Code pergunta se confia em cada pasta nova. '
                'Responda "Yes" uma vez nesta sessão e todas as worktrees '
                'do harness ficam confiáveis.',
              ),
            ),
            child: GhostButton(
              alignment: Alignment.centerLeft,
              leading: const Icon(LucideIcons.shieldCheck, size: 16),
              onPressed: () {
                store.prepareLiveAttach();
                d.send({
                  'type': 'trust_worktrees',
                  'account_id': store.workspaceAccounts.first.id,
                });
              },
              child: const Text('Confiar nas worktrees').small(),
            ),
          ),
      ],
    );
  }
}

Future<void> _dialog(BuildContext context, Widget child) => showOverlay<void>(
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
            child: child,
          ),
        ),
      );
    },
  ),
).future;

class _AddRepo extends StatefulWidget {
  const _AddRepo(this.store);

  final HarnessStore store;

  @override
  State<_AddRepo> createState() => _AddRepoState();
}

class _AddRepoState extends State<_AddRepo> {
  final _name = TextEditingController();
  final _path = TextEditingController();
  final _base = TextEditingController(text: 'main');

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _path]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _path, _base]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Adicionar repositório').large().semiBold(),
      const Text(
        'Um clone local. As sessões trabalham em worktrees dele, uma por branch.',
      ).xSmall().muted(),
      const Gap(16),
      const Text('Nome').small().medium(),
      const Gap(6),
      TextField(controller: _name, autofocus: true),
      const Gap(12),
      const Text('Caminho do clone').small().medium(),
      const Gap(6),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _path,
              placeholder: const Text('~/Project/meu-repo'),
            ),
          ),
          const Gap(6),
          OutlineButton(
            leading: const Icon(LucideIcons.folderOpen, size: 14),
            onPressed: () async {
              final picked = await showFolderPicker(
                context,
                widget.store,
                start: _path.text.trim().isEmpty ? null : _path.text.trim(),
              );
              if (picked == null) return;
              _path.text = picked;
              if (_name.text.trim().isEmpty) {
                _name.text = picked.split('/').where((p) => p.isNotEmpty).last;
              }
            },
            child: const Text('Escolher…'),
          ),
        ],
      ),
      const Gap(12),
      const Text('Branch base').small().medium(),
      const Gap(6),
      TextField(controller: _base),
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
            onPressed: _name.text.trim().isEmpty || _path.text.trim().isEmpty
                ? null
                : () {
                    widget.store.daemon!.addProject(
                      _name.text.trim(),
                      _path.text.trim(),
                      _base.text.trim(),
                      workspaceId: widget.store.workspaceId,
                    );
                    closeOverlay(context);
                  },
            child: const Text('Adicionar'),
          ),
        ],
      ),
    ],
  );
}

/// Branch names the daemon accepts (same rule as git::valid_branch).
final _branchRule = RegExp(r'^[A-Za-z0-9._][A-Za-z0-9._/-]*[A-Za-z0-9_-]$');

class _NewWorktree extends StatefulWidget {
  const _NewWorktree(this.store, this.projectId, this.projectName);

  final HarnessStore store;
  final String projectId;
  final String projectName;

  @override
  State<_NewWorktree> createState() => _NewWorktreeState();
}

class _NewWorktreeState extends State<_NewWorktree> {
  final _branch = TextEditingController(text: 'feat/');

  @override
  void initState() {
    super.initState();
    _branch.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _branch.dispose();
    super.dispose();
  }

  bool get _valid {
    final b = _branch.text.trim();
    return _branchRule.hasMatch(b) && !b.contains('..') && !b.contains('//');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.store.daemon!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Nova sessão em ${widget.projectName}').large().semiBold(),
        const Text(
          'Cria (ou reaproveita) a worktree da branch. Commits fora de conventional commits são recusados nela.',
        ).xSmall().muted(),
        const Gap(16),
        const Text('Branch').small().medium(),
        const Gap(6),
        TextField(controller: _branch, autofocus: true),
        if (!_valid && _branch.text.trim().length > 5) ...[
          const Gap(4),
          const Text(
            'Use letras, números, . _ / -; ex.: feat/12-login',
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
              onPressed: !_valid || widget.store.workspaceAccounts.isEmpty
                  ? null
                  : () {
                      widget.store.prepareLiveAttach();
                      d.createWorktreeSession(
                        widget.projectId,
                        _branch.text.trim(),
                        widget.store.workspaceAccounts.first.id,
                      );
                      closeOverlay(context);
                    },
              child: const Text('Criar sessão'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Navigates the Mac's folders through the daemon (also from the phone)
/// and returns the chosen one. Git repositories are marked.
Future<String?> showFolderPicker(
  BuildContext context,
  HarnessStore store, {
  String? start,
}) {
  store.daemon!.browseFolders(start);
  return showOverlay<String?>(
    context,
    DialogConfiguration<String?>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              padding: const EdgeInsets.all(16),
              child: _FolderPicker(store),
            ),
          ),
        );
      },
    ),
  ).future;
}

class _FolderPicker extends StatefulWidget {
  const _FolderPicker(this.store);

  final HarnessStore store;

  @override
  State<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<_FolderPicker> {
  bool _hidden = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.store.daemon!;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final f = d.folders;
        if (f == null) return const Center(child: Text('Carregando…'));
        final (path, parent, folders) = f;
        final parts = path.split('/').where((p) => p.isNotEmpty).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Escolher pasta').large().semiBold(),
            const Gap(8),
            // The path, each part clickable.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GhostButton(
                  size: ButtonSize.small,
                  onPressed: () => d.browseFolders('/', hidden: _hidden),
                  child: const Text('/'),
                ),
                for (final (i, p) in parts.indexed) ...[
                  GhostButton(
                    size: ButtonSize.small,
                    onPressed: () => d.browseFolders(
                      '/${parts.take(i + 1).join('/')}',
                      hidden: _hidden,
                    ),
                    child: Text(p),
                  ),
                  if (i < parts.length - 1) const Text('/').xSmall().muted(),
                ],
              ],
            ),
            Row(
              children: [
                if (parent != null)
                  GhostButton(
                    size: ButtonSize.small,
                    leading: const Icon(LucideIcons.arrowUp, size: 12),
                    onPressed: () => d.browseFolders(parent, hidden: _hidden),
                    child: const Text('Subir'),
                  ),
                GhostButton(
                  size: ButtonSize.small,
                  leading: const Icon(LucideIcons.house, size: 12),
                  onPressed: () => d.browseFolders(null, hidden: _hidden),
                  child: const Text('Início'),
                ),
                const Spacer(),
                GhostButton(
                  size: ButtonSize.small,
                  onPressed: () {
                    setState(() => _hidden = !_hidden);
                    d.browseFolders(path, hidden: _hidden);
                  },
                  child: Text(_hidden ? 'Esconder ocultas' : 'Mostrar ocultas'),
                ),
              ],
            ),
            const Divider(),
            Flexible(
              child: folders.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Nenhuma subpasta.'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final (name, repo) in folders)
                          GestureDetector(
                            onTap: () =>
                                d.browseFolders('$path/$name', hidden: _hidden),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      repo
                                          ? LucideIcons.gitBranch
                                          : LucideIcons.folder,
                                      size: 14,
                                    ),
                                    const Gap(8),
                                    Expanded(child: Text(name).small()),
                                    if (repo)
                                      const OutlineBadge(child: Text('git')),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const Divider(),
            const Gap(8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    path,
                    overflow: TextOverflow.ellipsis,
                  ).mono().xSmall().muted(),
                ),
                const Gap(8),
                OutlineButton(
                  onPressed: () => closeOverlay(context, null),
                  child: const Text('Cancelar'),
                ),
                const Gap(8),
                PrimaryButton(
                  onPressed: () => closeOverlay(context, path),
                  child: const Text('Usar esta pasta'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
