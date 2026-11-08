import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/live/live_terminal.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Map<String, dynamic> cellJson(String t) => {
  'text': t,
  'fg': {'kind': 'default'},
  'bg': {'kind': 'default'},
  'flags': 0,
};

Map<String, dynamic> diff(Map<int, String> rows) => {
  'cols': 10,
  'rows': 4,
  'lines': [
    for (final e in rows.entries)
      [
        e.key,
        [for (final ch in e.value.split('')) cellJson(ch)],
      ],
  ],
  'cursor': {'row': 0, 'col': 0, 'visible': true},
};

void main() {
  testWidgets('only changed rows are drawn again', (tester) async {
    final grid = LiveGrid()
      ..apply(diff({0: 'hello', 1: 'world', 2: '\$ ls', 3: ''}));
    await tester.pumpWidget(
      ShadcnApp(
        home: ListenableBuilder(
          listenable: grid,
          builder: (context, _) => LiveTerminal(
            grid: grid.state,
            onInput: (_) {},
            onResize: (_, _) {},
          ),
        ),
      ),
    );
    final first = debugRowsRecorded;
    expect(first, greaterThanOrEqualTo(4));

    // One row changes: one row recorded, the rest reused.
    grid.apply(diff({2: '\$ ls -la'}));
    await tester.pump();
    expect(debugRowsRecorded - first, 1);

    // Nothing changes (a cursor move repaints): nothing recorded.
    final second = debugRowsRecorded;
    grid.apply({
      ...diff({}),
      'cursor': {'row': 2, 'col': 4, 'visible': true},
    });
    await tester.pump();
    expect(debugRowsRecorded, second);
  });
}
