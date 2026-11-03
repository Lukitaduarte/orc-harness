import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/analytics_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  test('live usage rows keep token types, project and branch', () {
    final d = DaemonClient()
      ..handle(
        '{"type":"usage_report","rows":[{"day":"2026-11-03","account_id":"work","model":"claude-opus-5-5","project_id":"web","branch":"feat/1-login","usage":{"input":10,"output":5,"cache_read":80,"cache_creation":5,"cost_usd":0.5}}]}',
      );
    final r = d.usageRows.single;
    expect(
      (r.tokens, r.cacheRead, r.projectId, r.branch),
      (100, 80, 'web', 'feat/1-login'),
    );
    d.dispose();
  });

  testWidgets('analytics shows cache share, token types and cost per card', (
    tester,
  ) async {
    final store = HarnessStore();
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ShadcnApp(home: AnalyticsView(store)));
    expect(find.text('Lido do cache'), findsOneWidget);
    expect(
      find.text('81%'),
      findsOneWidget,
      reason: 'cache read over all prompt tokens',
    );
    expect(find.textContaining('Escrito no cache ·'), findsOneWidget);
    expect(find.text('Por projeto e branch (cards)'), findsOneWidget);
    expect(find.text('feat/3-get-users-com-cursor'), findsOneWidget);
    expect(find.text('sessões soltas'), findsWidgets);
    store.dispose();
  });
}
