import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/repos.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('a repository can be edited and removed; no trust button', (
    tester,
  ) async {
    final d = DaemonClient()..status = LinkStatus.connected;
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.handle('{"type":"hello","accounts":["work"]}');
    d.handle(
      '{"type":"projects","projects":[{"id":"mobile-platform","name":"mobile-platform","repo":"/r/mobile","base_branch":"main","workspace_id":null}]}',
    );
    store.selectWorkspace('live');
    // The test font is wide: room for the dialog's buttons.
    tester.view.physicalSize = const Size(2000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadcnApp(
        home: ListenableBuilder(
          listenable: store,
          builder: (c, _) => RepoSection(store),
        ),
      ),
    );
    expect(find.text('mobile-platform'), findsOneWidget);
    expect(find.text('Confiar nas worktrees'), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.settings2));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'develop');
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(sent.lastWhere((m) => m['type'] == 'update_project'), {
      'type': 'update_project',
      'id': 'mobile-platform',
      'name': 'mobile-platform',
      'base_branch': 'develop',
    });

    // Removing asks once more.
    await tester.tap(find.byIcon(LucideIcons.settings2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover repositório'));
    await tester.pump();
    expect(sent.where((m) => m['type'] == 'remove_project'), isEmpty);
    await tester.tap(find.text('Remover mesmo'));
    await tester.pumpAndSettle();
    expect(sent.lastWhere((m) => m['type'] == 'remove_project'), {
      'type': 'remove_project',
      'id': 'mobile-platform',
    });
    store.dispose();
    d.dispose();
  });
}
