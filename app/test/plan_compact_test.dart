import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/ui/plan_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('a plan fits a phone: approve and comment inside each section', (
    tester,
  ) async {
    final store = HarnessStore();
    final p = store.importPlan(
      '# Login social com um nome bem comprido para a tela\n\nResumo.\n\n## Fontes\nJira MOB-1.\n\n## Escopo\nGoogle e Apple.\n',
    );
    final first = p.plan!.sections.first;
    store.comment(p.plan!, first.id, first.title, 'e o iOS?');
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadcnApp(home: Scaffold(child: PlanView(store, p, compact: true))),
    );
    await tester.pump();
    // Nothing overflows a 390pt screen; the thread shows in its section.
    expect(tester.takeException(), isNull);
    expect(find.text('e o iOS?'), findsOneWidget);
    expect(find.text('Pedir revisão ao Claude'), findsOneWidget);
    await tester.tap(find.text('Aprovar').first);
    await tester.pump();
    expect(first.approved, isTrue);
    store.dispose();
  });
}
