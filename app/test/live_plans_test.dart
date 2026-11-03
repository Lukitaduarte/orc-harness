import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/live/live_plans.dart';
import 'package:orc_harness/src/model.dart';

const _markdown = '''
---
repo: Web
---
# Push

Notificações push no app.

## Fontes
Jira MOB-1.

## Execução
```loops
- title: Registrar token
  model: sonnet
  criteria: [token salvo]
  tasks:
    - { id: t1, title: Endpoint, skill: back, group: 1 }
- title: Tela de permissão
  model: haiku
  depends_on: [1]
```
''';

void main() {
  late DaemonClient d;
  late HarnessStore store;
  late List<Map<String, Object?>> sent;

  setUp(() {
    d = DaemonClient();
    store = HarnessStore(daemon: d);
    sent = [];
    d.sendHook = sent.add;
    d.handle('{"type":"hello","accounts":["work"]}');
    d.handle(
      '{"type":"projects","projects":[{"id":"web","name":"Web","repo":"/r","base_branch":"main"}]}',
    );
    d.handle(
      jsonEncode({
        'type': 'catalog',
        'entries': [],
        'templates': [
          {
            'id': 'app',
            'markdown':
                '---\nname: App\ndescription: d\n---\n# Feature\n\nResumo.\n\n## Fontes\n<!-- prompt: leia -->\nx\n',
          },
        ],
      }),
    );
    store.selectWorkspace('live');
  });

  tearDown(() {
    store.dispose();
    d.dispose();
  });

  void plans(List<Map<String, Object?>> docs) =>
      d.handle(jsonEncode({'type': 'plans', 'plans': docs}));

  Map<String, Object?> doc({
    Object? state,
    int revision = 1,
    bool busy = false,
  }) => {
    'id': 'push',
    'project_id': 'web',
    'name': 'Push',
    'markdown': _markdown,
    'state': state ?? {},
    'planner': 's9',
    'revision': revision,
    'busy': busy,
  };

  test('a new plan is saved and drafted by a planning session', () {
    final p = store.createLivePlan(
      repoId: 'web',
      name: 'Login social',
      description: 'Google e Apple',
      links: ['https://x.atlassian.net/browse/MOB-2'],
      template: store.planTemplates.first,
    );
    expect(store.openProject, p);
    expect(p.plan!.drafting, isTrue);
    expect(sent.map((m) => m['type']), ['save_plan', 'ask_planner']);
    final saved = sent[0]['plan'] as Map;
    expect(saved['project_id'], 'web');
    expect(
      saved['markdown'],
      startsWith(
        '---\nrepo: Web\nsources:\n  - https://x.atlassian.net/browse/MOB-2\n---\n# Login social\n\nGoogle e Apple\n\n## ',
      ),
    );
    expect(sent[1]['request'], contains('Google e Apple'));
    expect(sent[1]['account_id'], 'work');
  });

  test('review state round-trips and our own echo keeps the objects', () {
    plans([doc()]);
    final p = store.workspaceProjects.single;
    expect((p.name, p.repo, p.plan!.version), ('Push', 'Web', 2));
    final fontes = p.plan!.sections.first;

    store.comment(p.plan!, fontes.id, fontes.title, 'e o iOS?');
    store.approveSection(p.plan!.sections.last);
    final save = sent.last['plan'] as Map<String, Object?>;
    plans([save]);
    expect(store.workspaceProjects.single, same(p), reason: 'echo');

    // The planner answered: a new document, rebuilt with the reply.
    final state = jsonDecode(jsonEncode(save['state'])) as Map<String, dynamic>;
    (state['threads'] as List).first['messages'].add({
      'author': 'Claude',
      'body': 'incluí',
      'at': 1,
    });
    plans([
      {...save, 'state': state, 'revision': 2},
    ]);
    final again = store.workspaceProjects.single;
    expect(again, isNot(same(p)));
    final t = again.plan!.threads.single;
    expect(t.messages.map((m) => m.body), ['e o iOS?', 'incluí']);
    expect(t.awaitingAgent, isFalse);
    expect(again.plan!.sections.last.approved, isTrue);
    expect(again.plan!.sections.first.approved, isFalse);
  });

  test('review goes to the planner; start sends the cards; runs move them', () {
    plans([doc()]);
    var p = store.workspaceProjects.single;
    final plan = p.plan!;
    store.comment(plan, plan.sections.first.id, 'Fontes', 'falta o Figma');
    store.requestPlanReview(plan);
    expect(sent.last['type'], 'ask_planner');
    expect(sent.last['request'], contains('falta o Figma'));
    expect(
      sent.last['request'],
      contains('[thread ${plan.threads.single.id}]'),
    );

    for (final s in plan.sections) {
      store.approveSection(s);
    }
    store.setResolved(plan.threads.single, true);
    store.startExecution(p);
    final start = sent.last;
    expect(start['type'], 'start_plan');
    final cards = (start['cards'] as List).cast<Map<String, Object?>>();
    expect(
      cards.map((c) => '${c['number']} ${c['branch']} ${c['depends_on']}'),
      ['1 feat/1-registrar-token []', '2 feat/2-tela-de-permissao [1]'],
    );
    expect(cards.first['prompt'], contains('- token salvo'));
    expect(cards.first['prompt'], contains('grupo 1: Endpoint · back'));
    expect(store.readyCards(p), isEmpty, reason: 'the daemon starts them');

    plans([
      sent.firstWhere(
            (m) =>
                m['type'] == 'save_plan' &&
                ((m['plan'] as Map)['state'] as Map)['startedAt'] != null,
          )['plan']
          as Map<String, Object?>,
    ]);
    d.handle(
      jsonEncode({
        'type': 'plan_run',
        'plan_id': 'push',
        'cards': [
          {
            'number': 1,
            'state': 'review',
            'session_id': 's1',
            'branch': 'feat/1-registrar-token',
            'pr': 7,
            'pr_url': 'https://github.com/x/y/pull/7',
            'note': null,
          },
          {
            'number': 2,
            'state': 'failed',
            'session_id': null,
            'branch': 'feat/2-tela-de-permissao',
            'pr': null,
            'pr_url': null,
            'note': 'branch existe',
          },
        ],
      }),
    );
    p = store.workspaceProjects.single;
    expect(p.cards.map(p.columnOf), [
      KanbanColumn.review,
      KanbanColumn.blocked,
    ]);
    expect(p.cards.first.prUrl, 'https://github.com/x/y/pull/7');
    expect(p.cards.last.halt, contains('branch existe'));
    store.retryCard(p, p.cards.last);
    expect(sent.last, {'type': 'retry_card', 'plan_id': 'push', 'number': 2});
  });

  test('a busy planner shows as drafting first, reviewing later', () {
    plans([doc(revision: 0, busy: true)]);
    expect(store.workspaceProjects.single.plan!.drafting, isTrue);
    plans([doc(revision: 3, busy: true)]);
    final plan = store.workspaceProjects.single.plan!;
    expect((plan.drafting, plan.reviewing, plan.version), (false, true, 4));
    expect(plan.plannerSession, 's9');
  });

  test('canonical text ignores key order', () {
    expect(
      canonical({
        'b': 1,
        'a': [
          {'d': 2, 'c': 3},
        ],
      }),
      canonical({
        'a': [
          {'c': 3, 'd': 2},
        ],
        'b': 1,
      }),
    );
  });
}
