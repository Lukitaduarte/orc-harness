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

  test('live catalog, MCP tests, templates and profiles go through the daemon', () {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.handle('{"type":"hello","accounts":["default"]}');
    d.handle(
      '{"type":"catalog","entries":['
      '{"id":"skill-review","kind":"skill","name":"review","description":"","path":"/s/review","mcp":null,"has_value":false},'
      '{"id":"mcp-pg","kind":"mcp","name":"pg","description":"","path":null,"mcp":{"command":"npx","args":["pg"]},"has_value":false},'
      '{"id":"env-TOKEN","kind":"env","name":"TOKEN","description":"","path":null,"mcp":null,"has_value":true}],'
      '"templates":[{"id":"back","markdown":"---\\nname: Back end\\ndescription: Com deploy\\n---\\n# X\\n\\n## Deploy\\nok\\n"}]}',
    );
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"default","cwd":"/p","state":"idle","model":null,"claude_session_id":"u"}]}',
    );
    store.selectWorkspace('live');

    expect(store.catalog.map((i) => i.name), ['review', 'pg', 'TOKEN']);
    expect(store.catalog[1].detail, 'npx pg');
    expect(store.catalog[2].detail, contains('com valor'));
    expect(store.planTemplates.single.name, 'Back end');
    expect(store.planTemplates.single.description, 'Com deploy');

    // Adding an env sends the name to the catalog and the value to the
    // Keychain; nothing is kept in the app.
    sent.clear(); // drop the grid snapshot requests from 'sessions'
    store.addCatalogItem(
      CatalogKind.env,
      'API_KEY',
      '',
      '',
      secretValue: 's3cret',
    );
    expect(sent.map((m) => m['type']), ['upsert_catalog', 'set_secret']);
    expect((sent[0]['entry'] as Map)['name'], 'API_KEY');
    expect(
      store.catalog.any((i) => i.name == 'API_KEY'),
      isFalse,
    ); // until the daemon says so

    // A real MCP test: testing until the daemon answers.
    store.testMcp(store.catalog[1]);
    expect(store.mcpChecks['mcp-pg'], McpCheck.testing);
    d.handle(
      '{"type":"mcp_test","id":"mcp-pg","ok":true,"tools":7,"error":null}',
    );
    expect(store.mcpChecks['mcp-pg'], McpCheck.ok);
    expect(store.mcpResult('mcp-pg')!.$2, 7);

    // Applying a profile sends the stored MCP config and env names only.
    final s = store.session('s1');
    s.draftItems.addAll(['skill-review', 'mcp-pg', 'env-TOKEN']);
    sent.clear();
    store.applyDraft(s);
    final profile = sent.single['profile'] as Map;
    expect(profile['skills'], ['/s/review']);
    expect(profile['mcp_servers'], {
      'pg': {
        'command': 'npx',
        'args': ['pg'],
      },
    });
    expect(profile['env_names'], ['TOKEN']);
    store.dispose();
    d.dispose();
  });
}
