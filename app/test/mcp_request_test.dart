import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/agent_notices.dart';
import 'package:orc_harness/src/ui/catalog_view.dart';
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

  testWidgets('MCPs from Claude Code: new ones picked, secrets by name only', (
    tester,
  ) async {
    final d = DaemonClient();
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ShadcnApp(home: McpImportForm(d)));
    d.handle(
      '{"type":"mcp_imports","items":['
      '{"key":"a","label":"default · Claude Code","name":"railway","mcp":{"command":"npx","args":["railway-mcp"]},"secrets":["RAILWAY_TOKEN"],"in_catalog":false},'
      '{"key":"b","label":"default · app","name":"gh","mcp":{"type":"http","url":"https://gh/mcp"},"secrets":[],"in_catalog":true}]}',
    );
    await tester.pump();
    expect(find.text('railway'), findsOneWidget);
    expect(find.text('Para o Keychain: RAILWAY_TOKEN'), findsOneWidget);
    expect(find.text('https://gh/mcp'), findsOneWidget);
    await tester.tap(find.text('Importar 1'));
    await tester.pumpAndSettle();
    expect(sent.last, {
      'type': 'import_mcps',
      'keys': ['a'],
    });
    d.dispose();
  });
}
