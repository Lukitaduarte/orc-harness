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

  Map<String, Object?> _at(String path, int line, int character) => {
    'textDocument': {'uri': uriOf(path)},
    'position': {'line': line, 'character': character},
  };

  /// Where the symbol at a position is defined: (uri, line, character).
  Future<List<(String, int, int)>> definition(
    String path,
    int line,
    int character,
  ) async {
    final r = await request(
      'textDocument/definition',
      _at(path, line, character),
    );
    final list = r is List ? r : (r == null ? const [] : [r]);
    return [
      for (final l in list.cast<Map>())
        (
          (l['uri'] ?? l['targetUri']) as String,
          ((l['range'] ?? l['targetSelectionRange'])['start']['line'] as int),
          ((l['range'] ?? l['targetSelectionRange'])['start']['character']
              as int),
        ),
    ];
  }

  /// What the server says about the symbol at a position (plain text).
  Future<String?> hover(String path, int line, int character) async {
    final r = await request('textDocument/hover', _at(path, line, character));
    if (r is! Map) return null;
    final c = r['contents'];
    final text = switch (c) {
      String() => c,
      Map() => '${c['value'] ?? ''}',
      List() => c.map((x) => x is Map ? x['value'] : '$x').join('\n'),
      _ => '',
    };
    return text.trim().isEmpty ? null : text.trim();
  }

  /// The whole file formatted, or null if the server has nothing to change.
  Future<String?> format(String path, String text) async {
    final r = await request('textDocument/formatting', {
      'textDocument': {'uri': uriOf(path)},
      'options': {'tabSize': 2, 'insertSpaces': true},
    });
    if (r is! List || r.isEmpty) return null;
    return applyEdits(text, r.cast<Map<String, dynamic>>());
  }

  /// A file URI under the session's folder as a relative path, else null.
  String? relativeOf(String uri) {
    final root = Uri.directory(rootPath).toString();
    final private = root.replaceFirst('file:///', 'file:///private/');
    if (uri.startsWith(root)) {
      return Uri.decodeComponent(uri.substring(root.length));
    }
    if (uri.startsWith(private)) {
      return Uri.decodeComponent(uri.substring(private.length));
    }
    return null;
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

/// Applies LSP TextEdits (line/character, UTF-16 like Dart strings).
String applyEdits(String text, List<Map<String, dynamic>> edits) {
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 10) starts.add(i + 1);
  }
  int offset(Map p) {
    final line = p['line'] as int;
    if (line >= starts.length) return text.length;
    return (starts[line] + (p['character'] as int)).clamp(0, text.length);
  }

  final sorted = [...edits]
    ..sort(
      (a, b) =>
          offset(b['range']['start']).compareTo(offset(a['range']['start'])),
    );
  var out = text;
  for (final e in sorted) {
    out = out.replaceRange(
      offset(e['range']['start']),
      offset(e['range']['end']),
      e['newText'] as String,
    );
  }
  return out;
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
