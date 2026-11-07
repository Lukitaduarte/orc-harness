import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/live/local_daemon.dart';
import 'package:orc_harness/src/ui/onboarding.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('one permission at a time, each with its reason', (tester) async {
    final d = DaemonClient(local: LocalDaemon(bundled: null));
    var asked = 0;
    var done = false;
    // The test font is wide: room for the buttons' row.
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadcnApp(
        home: Onboarding(
          daemon: d,
          requestNotifications: () async => asked++,
          onDone: () => done = true,
        ),
      ),
    );
    // Welcome first; nothing asked yet.
    expect(find.text('Boas-vindas ao Orc Harness'), findsOneWidget);
    expect(asked, 0);
    await tester.tap(find.text('Vamos lá'));
    await tester.pumpAndSettle();

    // Notifications: the reason, then the prompt only on Conceder.
    expect(find.text('Notificações'), findsOneWidget);
    expect(find.textContaining('uma sessão espera você'), findsOneWidget);
    expect(asked, 0);
    // Without a bundled daemon this is the last step.
    await tester.tap(find.text('Conceder e terminar'));
    // The prompt and saving "done" are real async work.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(asked, 1);
    expect(done, isTrue);
    d.dispose();
  });
}
