import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../live/daemon_client.dart';
import '../i18n.dart';

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
                      Text(
                        context.l10n.devRepoBase('${p['base_branch']}'),
                      ).xSmall().muted(),
                    ],
                  ),
                ),
                Tooltip(
                  tooltip: (context) => TooltipContainer(
                    child: Text(context.l10n.devNewWorktreeSession),
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
        if (store.workspaceRepos.isNotEmpty &&
            store.workspaceAccounts.isNotEmpty)
          Tooltip(
            tooltip: (context) => TooltipContainer(
              child: Text(context.l10n.devTrustWorktreesHint),
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
              child: Text(context.l10n.devTrustWorktrees).small(),
            ),
          ),
      ],
    );
  }
}

/// "Adicionar repositório" (the + on the section title).
Future<void> showAddRepo(BuildContext context, HarnessStore store) =>
    _dialog(context, _AddRepo(store));

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
      Text(context.l10n.devAddRepository).large().semiBold(),
      Text(context.l10n.devAddRepositoryHint).xSmall().muted(),
      const Gap(16),
      Text(context.l10n.devName).small().medium(),
      const Gap(6),
      TextField(controller: _name, autofocus: true),
      const Gap(12),
      Text(context.l10n.devClonePath).small().medium(),
      const Gap(6),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _path,
              placeholder: Text(context.l10n.devClonePathPlaceholder),
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
            child: Text(context.l10n.devChoose),
          ),
        ],
      ),
      const Gap(12),
      Text(context.l10n.devBaseBranch).small().medium(),
      const Gap(6),
      TextField(controller: _base),
      const Gap(20),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlineButton(
            onPressed: () => closeOverlay(context),
            child: Text(context.l10n.devCancel),
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
            child: Text(context.l10n.devAdd),
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
        Text(
          context.l10n.devNewSessionIn(widget.projectName),
        ).large().semiBold(),
        Text(context.l10n.devNewWorktreeHint).xSmall().muted(),
        const Gap(16),
        Text(context.l10n.devBranch).small().medium(),
        const Gap(6),
        TextField(controller: _branch, autofocus: true),
        if (!_valid && _branch.text.trim().length > 5) ...[
          const Gap(4),
          Text(context.l10n.devBranchRule).xSmall().muted(),
        ],
        const Gap(20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlineButton(
              onPressed: () => closeOverlay(context),
              child: Text(context.l10n.devCancel),
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
              child: Text(context.l10n.devCreateSession),
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
        // Folders come from the daemon: say so when it is not there.
        if (d.status != LinkStatus.connected) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(context.l10n.devFoldersNoDaemon).small().muted(),
          );
        }
        if (f == null) return Center(child: Text(context.l10n.devLoading));
        final (path, parent, folders) = f;
        final parts = path.split('/').where((p) => p.isNotEmpty).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n.devChooseFolder).large().semiBold(),
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
                    child: Text(context.l10n.devFolderUp),
                  ),
                GhostButton(
                  size: ButtonSize.small,
                  leading: const Icon(LucideIcons.house, size: 12),
                  onPressed: () => d.browseFolders(null, hidden: _hidden),
                  child: Text(context.l10n.devFolderHome),
                ),
                const Spacer(),
                GhostButton(
                  size: ButtonSize.small,
                  onPressed: () {
                    setState(() => _hidden = !_hidden);
                    d.browseFolders(path, hidden: _hidden);
                  },
                  child: Text(
                    _hidden
                        ? context.l10n.devHideHidden
                        : context.l10n.devShowHidden,
                  ),
                ),
              ],
            ),
            const Divider(),
            Flexible(
              child: folders.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.l10n.devNoSubfolders),
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
                  child: Text(context.l10n.devCancel),
                ),
                const Gap(8),
                PrimaryButton(
                  onPressed: () => closeOverlay(context, path),
                  child: Text(context.l10n.devUseThisFolder),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
