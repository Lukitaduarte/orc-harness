import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/live/lsp_client.dart';
import 'package:orc_harness/src/ui/code_pane.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  test(
    'the LSP client matches answers, keeps diagnostics, answers the server',
    () async {
      final out = <Map<String, Object?>>[];
      final lsp = LspClient('/r/app', out.add);
      final init = lsp.start();
      expect(out.single['method'], 'initialize');
      expect((out.single['params'] as Map)['rootUri'], 'file:///r/app/');
      lsp.handle({
        'jsonrpc': '2.0',
        'id': out.single['id'],
        'result': {'capabilities': {}},
      });
      await init;
      expect(out.last['method'], 'initialized');

      lsp.handle({
        'jsonrpc': '2.0',
        'method': 'textDocument/publishDiagnostics',
        'params': {
          'uri': lsp.uriOf('lib/a.dart'),
          'diagnostics': [
            {'message': 'x'},
          ],
        },
      });
      expect(
        lsp.diagnostics['file:///r/app/lib/a.dart']!.single['message'],
        'x',
      );

      lsp.handle({
        'jsonrpc': '2.0',
        'id': 9,
        'method': 'workspace/configuration',
        'params': {
          'items': [{}, {}],
        },
      });
      expect(out.last, {
        'jsonrpc': '2.0',
        'id': 9,
        'result': [null, null],
      });

      expect(plainInsert(r'print(${1:object})$0'), 'print(object)');
      expect(languageOf('lib/main.dart'), 'dart');
      expect(languageOf('ios/Runner/AppDelegate.swift'), 'swift');
      expect(languageOf('README.md'), isNull);
      expect(
        (symbolKind(5), symbolKind(12), symbolKind(99)),
        ('classe', 'função', 'símbolo'),
      );
    },
  );

  testWidgets('the IDE pane lists the folder, opens a file and saves it', (
    tester,
  ) async {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.handle('{"type":"hello","accounts":["work"]}');
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"work","cwd":"/r/app","state":"idle","model":null,"claude_session_id":"u"}]}',
    );
    store.selectWorkspace('live');
    store.showSession('s1');
    store.openCode(store.focusedLeafId, 's1');
    expect(
      store.focusedSession,
      isNull,
      reason: 'the IDE pane is not a session',
    );

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadcnApp(
        home: CodePane(daemon: d, sessionId: 's1'),
      ),
    );
    expect(sent.last, {'type': 'list_dir', 'session_id': 's1', 'path': ''});
    d.handle(
      jsonEncode({
        'type': 'dir_entries',
        'session_id': 's1',
        'path': '',
        'entries': [
          {'name': 'lib', 'dir': true},
          {'name': 'README.md', 'dir': false},
        ],
      }),
    );
    await tester.pump();
    await tester.tap(find.text('README.md'));
    await tester.pump();
    expect(sent.last, {
      'type': 'read_file',
      'session_id': 's1',
      'path': 'README.md',
    });
    d.handle(
      jsonEncode({
        'type': 'file_content',
        'session_id': 's1',
        'path': 'README.md',
        'text': '# app\n',
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CodeEditor), findsOneWidget);

    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(sent.last, {
      'type': 'write_file',
      'session_id': 's1',
      'path': 'README.md',
      'text': '# app\n',
    });
    // re_editor's cursor blink outlives the editor unless it loses focus.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    d.dispose();
  });

  test('autocomplete filters the server items by the word being typed', () {
    final p = LspPrompts()
      ..update([
        {
          'label': 'print(Object? object)',
          'filterText': 'print',
          'insertText': r'print(${1:object})',
          'detail': 'void',
        },
        {'label': 'int', 'detail': 'class'},
      ]);
    final value = p.build(
      _FakeContext(),
      const CodeLine('  pri'),
      const CodeLineSelection.collapsed(index: 0, offset: 5),
    )!;
    expect(value.input, 'pri');
    expect(value.prompts.map((x) => x.word), ['print']);
    expect(value.autocomplete.word, 'print(object)');
    expect(
      p.build(
        _FakeContext(),
        const CodeLine('  '),
        const CodeLineSelection.collapsed(index: 0, offset: 2),
      ),
      isNull,
    );
  });
}

class _FakeContext extends Fake implements BuildContext {}
