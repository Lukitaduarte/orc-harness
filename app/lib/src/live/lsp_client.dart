import 'dart:async';

import 'package:flutter/foundation.dart';

/// The app's end of a language server the daemon runs for a session
/// (one per language). Full-document sync; diagnostics kept per file.
class LspClient extends ChangeNotifier {
  LspClient(this.rootPath, this._send);

  /// The session's folder; file URIs are under it.
  final String rootPath;
  final void Function(Map<String, Object?> message) _send;

  int _next = 1;
  final _pending = <int, Completer<Object?>>{};
  Future<Object?>? _ready;
  final _versions = <String, int>{};

  /// Diagnostics (LSP JSON) by file URI.
  final diagnostics = <String, List<Map<String, dynamic>>>{};

  String uriOf(String relPath) => Uri.file('$rootPath/$relPath').toString();

  Future<Object?> request(String method, Object? params) {
    final id = _next++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _send({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params});
    return c.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        return null;
      },
    );
  }

  void notify(String method, Object? params) =>
      _send({'jsonrpc': '2.0', 'method': method, 'params': params});

  /// `initialize` once, then `initialized`.
  Future<Object?> start() => _ready ??=
      request('initialize', {
        'processId': null,
        'rootUri': Uri.directory(rootPath).toString(),
        'capabilities': {
          'textDocument': {
            'completion': {
              'completionItem': {'snippetSupport': false},
            },
            'publishDiagnostics': {},
            'synchronization': {'didSave': true},
          },
          'workspace': {'configuration': true},
        },
      }).then((r) {
        notify('initialized', {});
        return r;
      });

  Future<void> open(String path, String languageId, String text) async {
    await start();
    _versions[path] = 1;
    notify('textDocument/didOpen', {
      'textDocument': {
        'uri': uriOf(path),
        'languageId': languageId,
        'version': 1,
        'text': text,
      },
    });
  }

  void change(String path, String text) {
    final v = (_versions[path] ?? 1) + 1;
    _versions[path] = v;
    notify('textDocument/didChange', {
      'textDocument': {'uri': uriOf(path), 'version': v},
      'contentChanges': [
        {'text': text},
      ],
    });
  }

  void saved(String path) => notify('textDocument/didSave', {
    'textDocument': {'uri': uriOf(path)},
  });

  /// Completion items at a position (LSP JSON).
  Future<List<Map<String, dynamic>>> complete(
    String path,
    int line,
    int character,
  ) async {
    final r = await request('textDocument/completion', {
      'textDocument': {'uri': uriOf(path)},
      'position': {'line': line, 'character': character},
    });
    final items = r is Map ? r['items'] : r;
    return items is List ? items.cast<Map<String, dynamic>>() : const [];
  }

  /// A message from the server, through the daemon.
  void handle(Map<String, dynamic> m) {
    final id = m['id'];
    final method = m['method'] as String?;
    if (method == null && id is int) {
      _pending.remove(id)?.complete(m['result']);
      return;
    }
    if (method == 'textDocument/publishDiagnostics') {
      final p = m['params'] as Map<String, dynamic>;
      diagnostics[p['uri'] as String] = (p['diagnostics'] as List)
          .cast<Map<String, dynamic>>();
      notifyListeners();
      return;
    }
    // Requests from the server need an answer; defaults are enough.
    if (method != null && id != null) {
      final result = switch (method) {
        'workspace/configuration' => [
          for (final _ in (m['params']?['items'] as List? ?? const [])) null,
        ],
        _ => null,
      };
      _send({'jsonrpc': '2.0', 'id': id, 'result': result});
    }
  }
}

/// LSP SymbolKind as a word.
String symbolKind(int k) => switch (k) {
  5 => 'classe',
  6 => 'método',
  7 || 8 => 'campo',
  9 => 'construtor',
  10 => 'enum',
  11 => 'interface',
  12 => 'função',
  13 => 'variável',
  14 => 'constante',
  22 => 'valor de enum',
  23 => 'struct',
  _ => 'símbolo',
};

/// The language a file is edited as, by extension (null: plain text).
String? languageOf(String path) => switch (path.split('.').last) {
  'dart' => 'dart',
  'ts' || 'tsx' || 'js' || 'jsx' => 'typescript',
  'kt' || 'kts' => 'kotlin',
  'swift' => 'swift',
  _ => null,
};

/// LSP insert text without snippet placeholders (`${1:x}` → x, `$0` → '').
String plainInsert(String text) => text
    .replaceAllMapped(RegExp(r'\$\{\d+:([^}]*)\}'), (m) => m.group(1)!)
    .replaceAll(RegExp(r'\$\{?\d+\}?'), '');
