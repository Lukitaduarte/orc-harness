import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import '../live/lsp_client.dart';

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

  /// Symbols (classes, functions…) from the language server instead of text.
  bool _symbols = false;
  List<Map<String, dynamic>>? _symbolHits;

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
    return (null, null, context.l10n.toolsNothingOpen);
  }

  /// The session's main language: TypeScript with a package.json, else Dart.
  String _language(String session) {
    final root = widget.store.daemon!.dirs[(session, '')] ?? const [];
    return root.any((e) => e['name'] == 'package.json') &&
            !root.any((e) => e['name'] == 'pubspec.yaml')
        ? 'typescript'
        : 'dart';
  }

  Future<void> _runSymbols(String session, String q) async {
    final lsp = widget.store.daemon!.lsp(session, _language(session));
    await lsp.start();
    final r = await lsp.request('workspace/symbol', {'query': q});
    // Only the session's own files (servers also list SDK symbols); macOS
    // may report /tmp-style paths under /private.
    final root = Uri.directory(lsp.rootPath).toString();
    final privateRoot = root.replaceFirst('file:///', 'file:///private/');
    String? local(Object? uri) {
      final u = '$uri';
      if (u.startsWith(root)) return u.substring(root.length);
      if (u.startsWith(privateRoot)) return u.substring(privateRoot.length);
      return null;
    }

    if (!mounted) return;
    setState(() {
      _symbolHits = [
        for (final s in (r is List ? r : const []).cast<Map<String, dynamic>>())
          if (local(s['location']?['uri']) case final path?)
            {
              'name': s['name'],
              'kind': symbolKind(s['kind'] as int? ?? 0),
              'path': path,
              'line':
                  ((s['location']?['range']?['start']?['line'] as int?) ?? 0) +
                  1,
            },
      ];
    });
  }

  void _run() {
    final q = _query.text.trim();
    final (session, project, _) = _scope();
    if (q.isEmpty || (session == null && project == null)) return;
    if (_symbols) {
      if (session != null) _runSymbols(session, q);
      return;
    }
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
        child: Text(context.l10n.toolsSearchNeedsDaemon).small().muted(),
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
                      placeholder: Text(context.l10n.toolsSearchIn(label)),
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
                  if (_scope().$1 != null)
                    _symbols
                        ? SecondaryButton(
                            onPressed: () => setState(() => _symbols = false),
                            child: Text(context.l10n.toolsSymbols),
                          )
                        : GhostButton(
                            onPressed: () => setState(() => _symbols = true),
                            child: Text(context.l10n.toolsSymbols),
                          ),
                  const Gap(4),
                  PrimaryButton(
                    onPressed: _run,
                    child: Text(context.l10n.toolsSearch),
                  ),
                ],
              ),
            ),
            const Divider(),
            if (result != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Text(
                  context.l10n.toolsResults(
                    '${result.$2.length}${result.$3 ? '+' : ''}',
                    result.$1,
                  ),
                ).xSmall().muted(),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  if (_symbols)
                    for (final h
                        in _symbolHits ?? const <Map<String, dynamic>>[])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: Text('${h['kind']}').xSmall().muted(),
                            ),
                            Expanded(
                              child: Text('${h['name']}').mono().xSmall(),
                            ),
                            Text(
                              '${h['path']}:${h['line']}',
                            ).mono().xSmall().muted(),
                          ],
                        ),
                      ),
                  if (!_symbols)
                    for (final h
                        in result?.$2 ?? const <Map<String, dynamic>>[])
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
