import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';

/// ⌘⇧F: text search in the focused session's folder, or the first
/// repository. The daemon walks the files (gitignore honored).
Future<void> showSearchDialog(BuildContext context, HarnessStore store) {
  return showOverlay<void>(
    context,
    DialogConfiguration<void>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints.tightFor(width: 820, height: 600),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              child: _Search(store),
            ),
          ),
        );
      },
    ),
  ).future;
}

class _Search extends StatefulWidget {
  const _Search(this.store);

  final HarnessStore store;

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  final _query = TextEditingController();
  bool _regex = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Where to search: the focused live session, else the first repository.
  (String?, String?, String) _scope() {
    final store = widget.store;
    final d = store.daemon;
    final s = store.focusedSession;
    if (s != null && s.live) return (s.id, null, s.branch);
    final repo = d?.projects.firstOrNull;
    if (repo != null) {
      return (null, repo['id'] as String, repo['name'] as String);
    }
    return (null, null, 'nada aberto');
  }

  void _run() {
    final q = _query.text.trim();
    final (session, project, _) = _scope();
    if (q.isEmpty || (session == null && project == null)) return;
    widget.store.daemon?.runSearch(
      q,
      sessionId: session,
      projectId: project,
      regex: _regex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.store.daemon;
    final (_, _, label) = _scope();
    if (d == null) {
      return Center(
        child: const Text(
          'Busca no código precisa do daemon conectado.',
        ).small().muted(),
      );
    }
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final result = d.search;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      autofocus: true,
                      placeholder: Text('Buscar em $label…'),
                      onSubmitted: (_) => _run(),
                    ),
                  ),
                  const Gap(8),
                  _regex
                      ? SecondaryButton(
                          onPressed: () => setState(() => _regex = false),
                          child: const Text('.*'),
                        )
                      : GhostButton(
                          onPressed: () => setState(() => _regex = true),
                          child: const Text('.*'),
                        ),
                  const Gap(4),
                  PrimaryButton(onPressed: _run, child: const Text('Buscar')),
                ],
              ),
            ),
            const Divider(),
            if (result != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Text(
                  '${result.$2.length}${result.$3 ? '+' : ''} resultado(s) para "${result.$1}"',
                ).xSmall().muted(),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  for (final h in result?.$2 ?? const <Map<String, dynamic>>[])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 260,
                            child: Text(
                              '${h['path']}:${h['line']}',
                              overflow: TextOverflow.ellipsis,
                            ).mono().xSmall().muted(),
                          ),
                          Expanded(
                            child: Text(
                              (h['text'] as String).trim(),
                            ).mono().xSmall(),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
