import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/sidebar.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets(
    'section titles carry the +; a session is deleted after you confirm',
    (tester) async {
      final d = DaemonClient();
      final store = HarnessStore(daemon: d);
      final sent = <Map<String, Object?>>[];
      d.sendHook = sent.add;
      d.handle('{"type":"hello","accounts":["work"]}');
      d.handle(
        '{"type":"sessions","sessions":[{"id":"s1","account_id":"work","cwd":"/r/app","state":"idle","model":null,"claude_session_id":"u"}]}',
      );
      store.selectWorkspace('live');
      tester.view.physicalSize = const Size(900, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ShadcnApp(home: Sidebar(store)));

      // No more bottom buttons: a + per section title, and Claude's mark.
      expect(find.text('Nova conta'), findsNothing);
      expect(find.text('Nova sessão'), findsNothing);
      expect(find.byIcon(LucideIcons.plus), findsNWidgets(4));
      expect(find.text('✻'), findsOneWidget);
      expect(find.text('Claude'), findsNothing);
      // ✻ name … : the mark first, the menu at the far end.
      final mark = tester.getCenter(find.text('✻')).dx;
      final name = tester.getCenter(find.text('work')).dx;
      final menu = tester.getCenter(find.byIcon(LucideIcons.ellipsis)).dx;
      expect(mark < name && name < menu, isTrue);

      // Right click on the session, confirm.
      await tester.tap(find.text('app'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Apagar a sessão app?'), findsOneWidget);
      await tester.tap(find.text('Apagar'));
      await tester.pumpAndSettle();
      expect(
        sent,
        anyElement(equals({'type': 'stop_session', 'session_id': 's1'})),
      );

      store.removeAccount('work');
      expect(sent.last, {'type': 'remove_account', 'id': 'work'});
      store.logoutAccount('work');
      expect(sent.last, {'type': 'logout_account', 'id': 'work'});
      store.dispose();
      d.dispose();
    },
  );

  test('deleting a plan ends its run on the daemon; demo plans just go', () {
    final store = HarnessStore();
    final p = store.projects.first;
    store.deleteProject(p);
    expect(store.projects.contains(p), isFalse);
    store.dispose();
  });
}
