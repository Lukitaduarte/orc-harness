import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/profile_panel.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets(
    'hundreds of skills: what is on first, the rest on demand or by search',
    (tester) async {
      final d = DaemonClient();
      final store = HarnessStore(daemon: d);
      final sent = <Map<String, Object?>>[];
      d.sendHook = sent.add;
      d.handle('{"type":"hello","accounts":["work"]}');
      d.handle(
        jsonEncode({
          'type': 'catalog',
          'entries': [
            for (var i = 0; i < 300; i++)
              {
                'id': 'skill-$i',
                'kind': 'skill',
                'name': 'skill-$i',
                'description': 'faz $i',
                'path': '/s/$i',
              },
          ],
          'templates': [],
        }),
      );
      // Restarting, with skill-7 on.
      d.handle(
        '{"type":"sessions","sessions":[{"id":"s1","account_id":"work","cwd":"/r","state":"starting","model":null,"claude_session_id":"u",'
        '"profile":{"skills":["/s/7"],"mcp_servers":{},"env_names":[],"model":null,"browser":null}}]}',
      );
      store.selectWorkspace('live');
      store.showSession('s1');
      tester.view.physicalSize = const Size(600, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ShadcnApp(
          home: ListenableBuilder(
            listenable: store,
            builder: (context, _) => ProfilePanel(store),
          ),
        ),
      );
      expect(find.text('SKILLS · 1 de 300 ligadas'), findsOneWidget);
      expect(find.text('skill-7'), findsOneWidget);
      expect(find.text('skill-8'), findsNothing, reason: 'the rest waits');
      expect(find.text('Mostrar as 299 disponíveis'), findsOneWidget);

      // A search shows matches; picking works while restarting.
      await tester.enterText(find.byType(TextField), 'skill-12');
      await tester.pump();
      expect(find.text('skill-12'), findsNWidgets(2), reason: 'field + row');
      expect(find.text('skill-123'), findsOneWidget);
      await tester.tap(find.text('skill-123'));
      await tester.pump();
      final s = store.sessions.firstWhere((s) => s.id == 's1');
      expect(s.draftItems, contains('skill-123'));
      // Applying waits for the restart.
      final apply = tester.widget<PrimaryButton>(
        find.ancestor(
          of: find.text('Aplicar'),
          matching: find.byType(PrimaryButton),
        ),
      );
      expect(apply.onPressed, isNull);
      store.dispose();
      d.dispose();
    },
  );
}
