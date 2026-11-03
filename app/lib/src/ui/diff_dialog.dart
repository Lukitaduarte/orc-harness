import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';

/// What a worktree session changed against its base, and its GitHub PR.
Future<void> showDiffDialog(
  BuildContext context,
  HarnessStore store,
  String sessionId,
) {
  store.daemon!.requestDiff(sessionId);
  return showOverlay<void>(
    context,
    DialogConfiguration<void>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints.tightFor(width: 1000, height: 680),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              child: ListenableBuilder(
                listenable: store.daemon!,
                builder: (context, _) => _Diff(store, sessionId),
              ),
            ),
          ),
        );
      },
    ),
  ).future;
}

class _Diff extends StatefulWidget {
  const _Diff(this.store, this.sessionId);

  final HarnessStore store;
  final String sessionId;

  @override
  State<_Diff> createState() => _DiffState();
}

class _DiffState extends State<_Diff> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final d = widget.store.daemon!;
    final diff = d.diffs[widget.sessionId];
    final pr = d.prs[widget.sessionId];
    final hasPr = d.prs.containsKey(widget.sessionId);
    final files = diff?.$2 ?? const [];
    final scheme = Theme.of(context).colorScheme;
    final selected = files.isEmpty
        ? null
        : files[_selected.clamp(0, files.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mudanças da sessão').large().semiBold(),
                    Text(
                      diff == null
                          ? 'Carregando…'
                          : '${files.length} arquivo(s) contra ${diff.$1}, incluindo o que ainda não foi commitado',
                    ).xSmall().muted(),
                  ],
                ),
              ),
              if (hasPr)
                pr == null
                    ? const OutlineBadge(child: Text('sem PR'))
                    : _PrChip(pr),
              const Gap(8),
              GhostButton(
                density: ButtonDensity.icon,
                onPressed: () => d.requestDiff(widget.sessionId),
                child: const Icon(LucideIcons.refreshCw, size: 14),
              ),
              GhostButton(
                density: ButtonDensity.icon,
                onPressed: () => closeOverlay(context),
                child: const Icon(LucideIcons.x, size: 16),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 280,
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final (i, f) in files.indexed)
                      GestureDetector(
                        onTap: () => setState(() => _selected = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: i == _selected ? scheme.accent : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                child: Text(
                                  f['status'] as String,
                                ).mono().xSmall().semiBold(),
                              ),
                              Expanded(
                                child: Text(
                                  f['path'] as String,
                                  overflow: TextOverflow.ellipsis,
                                ).mono().xSmall(),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(),
              Expanded(
                child: selected == null
                    ? Center(
                        child: const Text(
                          'Nenhuma mudança ainda.',
                        ).small().muted(),
                      )
                    : _Patch(
                        selected['patch'] as String,
                        untracked: selected['status'] == '?',
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrChip extends StatelessWidget {
  const _PrChip(this.pr);

  final Map<String, dynamic> pr;

  @override
  Widget build(BuildContext context) {
    final checks = (pr['statusCheckRollup'] as List?) ?? const [];
    final failing = checks
        .where((c) => (c as Map)['conclusion'] == 'FAILURE')
        .length;
    final state = pr['isDraft'] == true
        ? 'rascunho'
        : (pr['state'] as String).toLowerCase();
    return OutlineBadge(
      child: Text(
        'PR #${pr['number']} · $state'
        '${checks.isEmpty
            ? ''
            : failing > 0
            ? ' · $failing check(s) falhando'
            : ' · checks ok'}',
      ),
    );
  }
}

class _Patch extends StatelessWidget {
  const _Patch(this.patch, {required this.untracked});

  final String patch;
  final bool untracked;

  @override
  Widget build(BuildContext context) {
    if (untracked) {
      return Center(
        child: const Text(
          'Arquivo novo, ainda não rastreado pelo git.',
        ).small().muted(),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final lines = patch.split('\n');
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final l = lines[i];
        final (bg, fg) = switch (l) {
          _ when l.startsWith('+++') || l.startsWith('---') => (
            null,
            scheme.mutedForeground,
          ),
          _ when l.startsWith('+') => (
            Colors.emerald.withValues(alpha: 0.14),
            scheme.foreground,
          ),
          _ when l.startsWith('-') => (
            scheme.destructive.withValues(alpha: 0.14),
            scheme.foreground,
          ),
          _ when l.startsWith('@@') => (null, Colors.blue),
          _ when l.startsWith('diff --git') || l.startsWith('index ') => (
            null,
            scheme.mutedForeground,
          ),
          _ => (null, scheme.foreground),
        };
        return Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(l.isEmpty ? ' ' : l).mono().xSmall().medium(color: fg),
        );
      },
    );
  }
}
