import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/workspace_screen.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('the browser icon lights up while an agent drives it', (
    tester,
  ) async {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    d.sendHook = (_) {};
    d.handle('{"type":"hello","accounts":["w"]}');
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"w","cwd":"/r/app","state":"running","model":null,"claude_session_id":"u","branch":"feat/3-login"}]}',
    );
    store.selectWorkspace('live');
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ShadcnApp(home: WorkspaceScreen(store)));
    expect(find.byKey(const ValueKey('in-use')), findsNothing);

    d.handle('{"type":"browser_use","profile":"live","session_id":"s1"}');
    await tester.pump();
    expect(find.byKey(const ValueKey('in-use')), findsOneWidget);
    expect(d.browserOf('live').usedBy, 's1');
    expect(d.sessionLabel('s1'), 'feat/3-login');

    d.handle('{"type":"browser_use","profile":"live","session_id":null}');
    await tester.pump();
    expect(find.byKey(const ValueKey('in-use')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    d.dispose();
  });
}
