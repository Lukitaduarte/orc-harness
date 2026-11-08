import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/agent_notices.dart';
import 'package:orc_harness/src/ui/catalog_view.dart';
import 'package:orc_harness/src/ui/profile_panel.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

const _catalog =
    '{"type":"catalog","entries":['
    '{"id":"mcp-gh","kind":"mcp","name":"gh","mcp":{"command":"npx","args":["gh-mcp"],"env":{"GH_TOKEN":"\${GH_TOKEN}"}}},'
    '{"id":"env-GH_TOKEN","kind":"env","name":"GH_TOKEN","has_value":false}],"templates":[]}';

void main() {
  testWidgets('an agent asks for an MCP; you see what runs and approve', (
    tester,
  ) async {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.handle('{"type":"hello","accounts":["work"]}');
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"work","cwd":"/r/app","state":"idle","model":null,"claude_session_id":"u"}]}',
    );
    d.handle(
      '{"type":"mcp_request","id":"r1","session_id":"s1","name":"gh","mcp":{"command":"npx","args":["gh-mcp"]},"reason":"abrir PRs"}',
    );
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ShadcnApp(home: AgentNotices(store)));
    expect(find.textContaining('pede para adicionar o MCP gh'), findsOneWidget);
    expect(find.text('abrir PRs'), findsOneWidget);
    expect(find.text('npx gh-mcp'), findsOneWidget);
    await tester.tap(find.text('Aprovar e reiniciar'));
    await tester.pump();
    expect(sent.last, {
      'type': 'resolve_mcp_request',
      'id': 'r1',
      'approve': true,
    });
    expect(d.mcpRequests, isEmpty);
    store.dispose();
    d.dispose();
  });

  test('what a session runs with comes from the daemon', () {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    d.sendHook = (_) {};
    d.handle('{"type":"hello","accounts":["work"]}');
    d.handle(_catalog);
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"work","cwd":"/r/app","state":"idle","model":null,"claude_session_id":"u",'
      '"profile":{"skills":[],"mcp_servers":{"gh":{}},"env_names":["GH_TOKEN"],"model":null,"browser":null}}]}',
    );
    final s = store.sessions.firstWhere((s) => s.id == 's1');
    expect(s.appliedItems, {'mcp-gh', 'env-GH_TOKEN'});
    expect(s.hasPendingChanges, isFalse);
    store.dispose();
    d.dispose();
  });

  test('turning an MCP on brings the envs it references', () {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.handle('{"type":"hello","accounts":["work"]}');
    d.handle(_catalog);
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"work","cwd":"/r/app","state":"idle","model":null,"claude_session_id":"u"}]}',
    );
    final s = store.sessions.firstWhere((s) => s.id == 's1');
    s.draftItems = {'mcp-gh'};
    store.applyDraft(s);
    final profile = sent.last['profile'] as Map;
    expect(profile['env_names'], ['GH_TOKEN']);
    store.dispose();
    d.dispose();
  });

  testWidgets('import from this Mac: grouped by source, searchable, skills too', (
    tester,
  ) async {
    final d = DaemonClient();
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ShadcnApp(home: McpImportForm(d)));
    d.handle(
      '{"type":"mcp_imports","items":['
      '{"key":"a","kind":"mcp","label":"Claude Code ~/.claude-personal","name":"railway","mcp":{"command":"npx","args":["railway-mcp"]},"secrets":["RAILWAY_TOKEN"],"in_catalog":false},'
      '{"key":"b","kind":"mcp","label":"Cursor","name":"gh","mcp":{"type":"http","url":"https://gh/mcp"},"secrets":[],"in_catalog":true},'
      '{"key":"s1","kind":"skill","label":"plugin dart-flutter · ~/.claude","name":"dart-add-test","description":"Write unit tests","mcp":null,"secrets":[],"in_catalog":false},'
      '{"key":"s2","kind":"skill","label":"plugin dart-flutter · ~/.claude","name":"dart-fix","description":"","mcp":null,"secrets":[],"in_catalog":false}]}',
    );
    await tester.pump();
    // Sources are groups with counts; new MCPs picked, skills not.
    expect(find.text('Claude Code ~/.claude-personal  ·  1'), findsOneWidget);
    expect(find.text('plugin dart-flutter · ~/.claude  ·  2'), findsOneWidget);
    expect(find.text('Importar 1'), findsOneWidget);
    expect(find.text('railway'), findsNothing, reason: 'groups start closed');

    // A search opens the groups that match.
    await tester.enterText(find.byType(TextField), 'railway');
    await tester.pump();
    // The field holds the query too.
    expect(find.text('railway'), findsNWidgets(2));
    expect(find.text('Para o Keychain: RAILWAY_TOKEN'), findsOneWidget);
    expect(find.text('dart-add-test'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    // Picking a whole source: groups are closed, one box each (the
    // skills group is the third).
    expect(find.byType(Checkbox), findsNWidgets(3));
    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pump();
    await tester.tap(find.text('Importar 3'));
    await tester.pumpAndSettle();
    expect(sent.last['type'], 'import_mcps');
    expect((sent.last['keys'] as List).toSet(), {'a', 's1', 's2'});
    d.dispose();
  });

  testWidgets('claude.ai connectors are picked per session', (tester) async {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.handle('{"type":"hello","accounts":["work"]}');
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"work","cwd":"/r/app","state":"idle","model":null,"claude_session_id":"u"}]}',
    );
    store.selectWorkspace('live');
    store.showSession('s1');
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadcnApp(
        home: ListenableBuilder(
          listenable: Listenable.merge([store, d]),
          builder: (context, _) => ProfilePanel(store),
        ),
      ),
    );
    await tester.pump();
    // Asked for once, for the session's account.
    expect(sent.where((m) => m['type'] == 'list_connectors').single, {
      'type': 'list_connectors',
      'account_id': 'work',
    });
    d.handle(
      '{"type":"connectors","account_id":"work","items":['
      '{"name":"Gmail","url":"https://gmail/mcp","status":"connected"},'
      '{"name":"Slack","url":"https://slack/mcp","status":"needs_auth"}]}',
    );
    await tester.pump();
    expect(find.text('Gmail'), findsOneWidget);
    expect(find.text('Não conectado: conecte no claude.ai'), findsOneWidget);
    await tester.tap(find.text('Gmail'));
    await tester.pump();
    store.applyDraft(store.sessions.firstWhere((s) => s.id == 's1'));
    final profile = sent.last['profile'] as Map;
    expect(profile['connectors'], ['https://gmail/mcp']);
    store.dispose();
    d.dispose();
  });
}
