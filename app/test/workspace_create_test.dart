import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/workspace_dialogs.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('a new workspace reaches the daemon and opens', (tester) async {
    final d = DaemonClient()..status = LinkStatus.connected;
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.handle('{"type":"hello","accounts":["Lukita-me","Personal"]}');
    d.handle(
      '{"type":"workspaces","workspaces":[{"id":"default","name":"Este Mac","accounts":["Lukita-me","Personal"],"memory":null,"budget_usd":null}]}',
    );
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadcnApp(
        home: Builder(
          builder: (context) => PrimaryButton(
            onPressed: () => showWorkspaceDialog(context, store),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Trabalho');
    await tester.pump();
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();
    final up = sent.where((m) => m['type'] == 'upsert_workspace').toList();
    expect(up, hasLength(1), reason: '$sent');
    expect((up.single['workspace'] as Map)['id'], 'trabalho');
    d.handle(
      '{"type":"workspaces","workspaces":['
      '{"id":"default","name":"Este Mac","accounts":["Lukita-me","Personal"],"memory":null,"budget_usd":null},'
      '{"id":"trabalho","name":"Trabalho","accounts":[],"memory":null,"budget_usd":null}]}',
    );
    expect(store.workspaceId, 'trabalho');
    store.dispose();
    d.dispose();
  });

  testWidgets(
    'without the daemon the dialog says so instead of doing nothing',
    (tester) async {
      final d = DaemonClient();
      final store = HarnessStore(daemon: d);
      d.sendHook = (_) {};
      d.handle('{"type":"hello","accounts":["a"]}');
      d.status = LinkStatus.disconnected;
      await tester.pumpWidget(
        ShadcnApp(
          home: Builder(
            builder: (context) => PrimaryButton(
              onPressed: () => showWorkspaceDialog(context, store),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Trabalho');
      await tester.pump();
      expect(
        find.textContaining('O daemon não está conectado'),
        findsOneWidget,
      );
      final create = tester.widget<PrimaryButton>(
        find.ancestor(
          of: find.text('Criar'),
          matching: find.byType(PrimaryButton),
        ),
      );
      expect(create.onPressed, isNull);
      store.dispose();
      d.dispose();
    },
  );
}
