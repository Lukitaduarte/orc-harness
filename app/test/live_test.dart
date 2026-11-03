import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/live/grid.dart';
import 'package:orc_harness/src/model.dart';

/// Same string as GRID_DIFF_JSON in crates/protocol (pinned on both sides).
const gridDiffJson =
    r'{"type":"grid_diff","session_id":"s1","diff":{"cols":4,"rows":2,"lines":[[1,[{"text":"h","fg":{"kind":"indexed","index":1},"bg":{"kind":"default"},"flags":1},{"text":"i","fg":{"kind":"rgb","r":1,"g":2,"b":3},"bg":{"kind":"default"},"flags":0}]]],"cursor":{"row":1,"col":2,"visible":true}}}';

void main() {
  test('grid diffs from the daemon apply cell by cell', () {
    final d = DaemonClient()..handle(gridDiffJson);
    final g = d.grids['s1']!.state;
    expect((g.cols, g.rows), (4, 2));
    expect(g.lineText(1), 'hi');
    expect(g.lines[1][0].has(TermCell.bold), isTrue);
    expect(g.lines[1][0].fg, isNotNull);
    expect(g.lines[1][1].fg!.toARGB32(), 0xFF010203);
    expect(g.lines[1][0].bg, isNull);
    expect((g.cursorRow, g.cursorCol), (1, 2));
    d.dispose();
  });

  test('the daemon state becomes the "Este Mac" workspace', () {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    d.handle('{"type":"hello","accounts":["default"]}');
    expect(store.workspaces.last.id, 'live');

    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"default","cwd":"/Users/x/Project/app","state":"starting","model":null,"claude_session_id":"u"}]}',
    );
    store.selectWorkspace('live');
    final s = store.workspaceSessions.single;
    expect(s.live, isTrue);
    expect(s.name, 'app');
    expect(store.workspaceAccounts.single.hasReading, isFalse);

    d.handle(
      '{"type":"session_state","session_id":"s1","state":"waiting_input"}',
    );
    expect(store.session('s1').state, SessionState.waitingInput);

    d.handle(
      '{"type":"quota","account_id":"default","limits":{"five_hour":{"used_percentage":62.5,"resets_at":1738425600},"seven_day":null},"read_at":1738420000}',
    );
    final acc = store.workspaceAccounts.single;
    expect(acc.hasReading, isTrue);
    expect(acc.fiveHour.usedPercent, 62.5);

    // A session that ends leaves its pane empty.
    store.showSession('s1');
    d.handle('{"type":"sessions","sessions":[]}');
    expect(store.workspaceSessions, isEmpty);
    expect(store.focusedSession, isNull);
    store.dispose();
    d.dispose();
  });
}
