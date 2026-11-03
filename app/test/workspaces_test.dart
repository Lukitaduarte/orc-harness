import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';

void main() {
  test('the daemon workspaces replace the demo ones', () {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    expect(store.demo, isFalse);
    expect(store.workspaces.map((w) => w.id), [
      'live',
    ], reason: 'until the daemon reports');

    d.handle('{"type":"hello","accounts":["a","b"]}');
    d.handle(
      jsonEncode({
        'type': 'workspaces',
        'workspaces': [
          {
            'id': 'trabalho',
            'name': 'Trabalho',
            'accounts': ['a'],
          },
          {
            'id': 'pessoal',
            'name': 'Pessoal Lucas',
            'accounts': ['b'],
          },
        ],
      }),
    );
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"a","cwd":"/w","state":"idle","model":null,"claude_session_id":"u"},{"id":"s2","account_id":"b","cwd":"/p","state":"idle","model":null,"claude_session_id":"u"}]}',
    );
    d.handle(
      jsonEncode({
        'type': 'projects',
        'projects': [
          {
            'id': 'web',
            'name': 'Web',
            'repo': '/w',
            'base_branch': 'main',
            'workspace_id': 'trabalho',
          },
          {
            'id': 'blog',
            'name': 'Blog',
            'repo': '/b',
            'base_branch': 'main',
            'workspace_id': 'pessoal',
          },
        ],
      }),
    );
    expect(store.workspaces.map((w) => (w.id, w.initials)), [
      ('trabalho', 'TR'),
      ('pessoal', 'PL'),
    ]);
    expect(store.workspaceId, 'trabalho', reason: 'the placeholder went away');
    expect(store.workspaceAccounts.map((a) => a.id), ['a']);
    expect(store.workspaceSessions.map((s) => s.id), ['s1']);
    expect(store.workspaceRepos.map((r) => r['id']), ['web']);
    store.selectWorkspace('pessoal');
    expect(store.workspaceSessions.map((s) => s.id), ['s2']);
    expect(store.workspaceRepos.map((r) => r['id']), ['blog']);

    // A new workspace is created and selected once the daemon has it.
    store.saveWorkspace('Cliente X', ['b']);
    expect(sent.last, {
      'type': 'upsert_workspace',
      'workspace': {
        'id': 'cliente-x',
        'name': 'Cliente X',
        'accounts': ['b'],
        'memory': null,
        'budget_usd': null,
      },
    });
    d.handle(
      jsonEncode({
        'type': 'workspaces',
        'workspaces': [
          {
            'id': 'trabalho',
            'name': 'Trabalho',
            'accounts': ['a'],
          },
          {'id': 'pessoal', 'name': 'Pessoal Lucas', 'accounts': []},
          {
            'id': 'cliente-x',
            'name': 'Cliente X',
            'accounts': ['b'],
          },
        ],
      }),
    );
    expect(store.workspaceId, 'cliente-x');
    expect(
      store.workspaceSessions.map((s) => s.id),
      ['s2'],
      reason: 'sessions follow their account',
    );

    // A new account opens a session on it for the login.
    store.addAccount('c');
    expect(sent.last, {
      'type': 'add_account',
      'id': 'c',
      'workspace_id': 'cliente-x',
    });
    d.handle('{"type":"hello","accounts":["a","b","c"]}');
    expect(sent.last['type'], 'create_session');
    expect(sent.last['account_id'], 'c');

    // Memory: the provider goes with the workspace; you see and clean entries.
    store.saveWorkspace(
      'Cliente X',
      ['b'],
      id: 'cliente-x',
      memory: 'mcp-mem0',
    );
    expect((sent.last['workspace'] as Map)['memory'], 'mcp-mem0');
    expect(
      store.memoryOf('trabalho'),
      'orc',
      reason: 'the harness memory by default',
    );
    d.handle(
      jsonEncode({
        'type': 'memory',
        'workspace_id': 'trabalho',
        'entries': [
          {
            'id': 'm1',
            'at': 1,
            'session': 's1',
            'text': 'Deploy no Railway',
            'tags': [],
          },
        ],
      }),
    );
    expect(d.memory['trabalho']!.single['text'], 'Deploy no Railway');
    d.forgetMemory('trabalho', 'm1');
    expect(sent.last, {
      'type': 'forget_memory',
      'workspace_id': 'trabalho',
      'id': 'm1',
    });

    store.deleteWorkspace('pessoal');
    expect(sent.last, {'type': 'remove_workspace', 'id': 'pessoal'});
    store.dispose();
    d.dispose();
  });

  test('without a daemon the demo workspaces show', () {
    final store = HarnessStore();
    expect(store.demo, isTrue);
    expect(store.workspaces.length, greaterThan(1));
    store.dispose();
  });

  test('a budget warns at 80% and past 100%, once each', () {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    final alerts = <String>[];
    d.onAlert = (t, _) => alerts.add(t);
    d.sendHook = (_) {};
    d.handle('{"type":"hello","accounts":["a"]}');
    final today = store.now.toUtc().toIso8601String().substring(0, 10);
    void usage(double cost) => d.handle(
      jsonEncode({
        'type': 'usage_report',
        'rows': [
          {
            'day': today,
            'account_id': 'a',
            'model': 'm',
            'usage': {
              'input': 1,
              'output': 1,
              'cache_read': 0,
              'cache_creation': 0,
              'cost_usd': cost,
            },
          },
        ],
      }),
    );
    d.handle(
      jsonEncode({
        'type': 'workspaces',
        'workspaces': [
          {
            'id': 'trabalho',
            'name': 'Trabalho',
            'accounts': ['a'],
            'budget_usd': 100,
          },
        ],
      }),
    );
    expect(store.budgetOf('trabalho'), 100);
    usage(50);
    expect(alerts, isEmpty);
    usage(85);
    usage(86);
    expect(alerts, ['Orçamento em 80%']);
    usage(120);
    usage(130);
    expect(alerts, ['Orçamento em 80%', 'Orçamento estourado']);
    expect(store.monthCost('trabalho'), 130);
    store.dispose();
    d.dispose();
  });
}
