import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/profile_panel.dart';
import 'package:orc_harness/src/ui/sidebar.dart';
import 'package:orc_harness/src/ui/workspace_screen.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  for (final (w, h, sidebar) in [
    (800.0, 630.0, false),
    (1000.0, 700.0, true),
    (1500.0, 900.0, true),
  ]) {
    testWidgets('a ${w.toInt()}x${h.toInt()} window lays out cleanly', (
      tester,
    ) async {
      final d = DaemonClient();
      final store = HarnessStore(daemon: d);
      d.sendHook = (_) {};
      d.handle('{"type":"hello","accounts":["w"]}');
      store.selectWorkspace('live');
      tester.view.physicalSize = Size(w, h);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ShadcnApp(home: WorkspaceScreen(store)));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'no overflow at ${w}x$h');
      expect(find.byType(Sidebar), sidebar ? findsOneWidget : findsNothing);
      expect(
        find.byType(ProfilePanel),
        findsNothing,
        reason: 'no session: no profile panel',
      );
      // Splitting the only pane still fits.
      store.split(store.focusedLeafId, horizontal: true);
      await tester.pump();
      expect(tester.takeException(), isNull);
      // The sidebar comes back by hand.
      if (!sidebar) {
        await tester.tap(find.byIcon(LucideIcons.panelLeft));
        await tester.pump();
        expect(find.byType(Sidebar), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      d.dispose();
    });
  }
}
