import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/live_input_bar.dart';
import 'package:orc_harness/src/ui/mobile_shell.dart';
import 'package:orc_harness/src/ui/workspace_screen.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  test('one line is typed and sent; several go as one paste', () {
    expect(LiveInputBar.encode('oi'), ['oi', '\r']);
    expect(LiveInputBar.encode('a\nb'), ['\x1b[200~a\nb\x1b[201~', '\r']);
  });

  testWidgets('a phone gets quotas, sessions and a session with input', (
    tester,
  ) async {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.handle('{"type":"hello","accounts":["work"]}');
    d.handle(
      '{"type":"quota","account_id":"work","limits":{"five_hour":{"used_percentage":40,"resets_at":1999999999},"seven_day":{"used_percentage":12,"resets_at":1999999999}},"read_at":1738420000}',
    );
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"work","cwd":"/Users/x/app","state":"idle","model":null,"claude_session_id":"u"}]}',
    );
    store.selectWorkspace('live');

    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ShadcnApp(home: WorkspaceScreen(store)));
    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.text('40%'), findsOneWidget, reason: '5h quota in sight');
    expect(find.text('12%'), findsOneWidget, reason: 'weekly quota in sight');

    await tester.tap(find.text('app'));
    await tester.pumpAndSettle();
    expect(find.byType(LiveInputBar), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'rode os testes');
    await tester.tap(find.byIcon(LucideIcons.send));
    await tester.tap(find.text('Esc'));
    final inputs = sent
        .where((m) => m['type'] == 'input')
        .map((m) => m['data'])
        .toList();
    expect(inputs, ['rode os testes', '\r', '\x1b']);

    store.dispose();
    d.dispose();
  });
}
