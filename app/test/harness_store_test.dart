import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/model.dart';

List<String> leafIds(LayoutNode n) => switch (n) {
  LayoutLeaf() => [n.id],
  LayoutSplit() => [for (final c in n.children) ...leafIds(c)],
};

void main() {
  late HarnessStore store;

  setUp(() => store = HarnessStore());
  tearDown(() => store.dispose());

  test('split in the parent direction adds a sibling instead of nesting', () {
    // Work layout: root is horizontal [p-api, right(vertical)].
    store.split('p-api', horizontal: true);
    final root = store.layout as LayoutSplit;
    expect(root.children, hasLength(3));
    expect(root.children[1], isA<LayoutLeaf>());
    expect((root.children[1] as LayoutLeaf).sessionId, isNull);
    expect(store.focusedLeafId, root.children[1].id);
  });

  test('split across the parent direction nests a new split', () {
    store.split('p-api', horizontal: false);
    final root = store.layout as LayoutSplit;
    final nested = root.children.first as LayoutSplit;
    expect(nested.horizontal, isFalse);
    expect(leafIds(nested).first, 'p-api');
  });

  test('closing a pane collapses a split left with one child', () {
    store.close('p-front');
    final root = store.layout as LayoutSplit;
    expect(leafIds(root), ['p-api', 'p-review']);
    expect(root.children.last, isA<LayoutLeaf>());
  });

  test('the last pane is emptied, never removed', () {
    store.selectWorkspace('personal');
    store.close('p-fenda');
    final root = store.layout;
    expect(root, isA<LayoutLeaf>());
    expect((root as LayoutLeaf).sessionId, isNull);
  });

  test('showing a visible session focuses its pane', () {
    store.showSession('review');
    expect(store.focusedLeafId, 'p-review');
  });

  test('profile changes stay pending until applied', () {
    final s = store.session('api');
    store.toggleItem(s, 'linear');
    expect(s.hasPendingChanges, isTrue);
    store.applyDraft(s);
    expect(s.hasPendingChanges, isFalse);
    expect(s.state, SessionState.starting);
  });

  group('kanban', () {
    Project users() =>
        store.projects.firstWhere((p) => p.id == 'users-pagination');

    test('columns come from the dependency graph', () {
      final p = users();
      expect(p.columnOf(p.card(5)), KanbanColumn.blocked); // waits on #3, #4
      expect(p.columnOf(p.card(6)), KanbanColumn.ready); // #1 is done
      expect(p.columnOf(p.card(3)), KanbanColumn.running);
    });

    test('running a card opens its own session on the freest account', () {
      final p = users();
      store.runCard(p, p.card(6));
      final c = p.card(6);
      expect(c.state, CardState.running);
      final s = store.session(c.sessionId!);
      expect(s.branch, 'docs/6-documentar-o-contrato-na-api-publica');
      expect(s.model, 'haiku');
      expect(s.accountId, 'work-main'); // 62% beats work-alt's 91%
    });

    test('blocked cards do not run', () {
      final p = users();
      store.runCard(p, p.card(5));
      expect(p.card(5).state, CardState.todo);
    });

    test('runReady respects the concurrency limit', () {
      final p = store.projects.firstWhere((p) => p.id == 'onboarding-v2');
      store.runReady(p); // only #1 is ready
      store.simulatePr(p.card(1));
      store.simulateMerge(p.card(1)); // #2 and #3 become ready
      expect(store.readyCards(p).map((c) => c.number), [2, 3]);
      store.runReady(p);
      expect(store.runningCount(p), 2);
      expect(
        store.runningCount(p),
        lessThanOrEqualTo(HarnessStore.maxRunningCards),
      );
    });

    test('merging the last dependencies unblocks dependents', () {
      final p = users();
      for (final n in [3, 4]) {
        store.simulatePr(p.card(n));
        store.simulateMerge(p.card(n));
      }
      expect(p.columnOf(p.card(5)), KanbanColumn.ready);
      expect(p.columnOf(p.card(7)), KanbanColumn.blocked); // still waits on #5
    });
  });

  test('accent folding lets "sessao" match "Sessões"', () {
    expect(foldAccents('Sessões'), 'sessoes');
  });

  group('plan mode', () {
    Project push() =>
        store.projects.firstWhere((p) => p.id == 'push-notifications');

    void approveAll(Plan plan) {
      for (final s in plan.sections) {
        store.approveSection(s);
      }
    }

    test('execution needs every section approved', () {
      final p = push();
      expect(p.plan!.approvedCount, 4);
      store.startExecution(p);
      expect(p.isPlanning, isTrue);
      approveAll(p.plan!);
      expect(p.plan!.canStart, isTrue);
    });

    test('approval is final: a change to an approved section blocks start', () {
      final plan = push().plan!;
      approveAll(plan);
      final s = plan.section('escopo');
      s.blocks = [...s.blocks, const TextBlock('mudança silenciosa')];
      expect(s.changedAfterApproval, isTrue);
      expect(plan.canStart, isFalse);
    });

    test('starting moves the loops to the board and runs the ready ones', () {
      final p = push();
      approveAll(p.plan!);
      store.startExecution(p);
      expect(p.isPlanning, isFalse);
      expect(p.cards, hasLength(5));
      expect(p.card(1).state, CardState.running); // the only loop with no deps
      // the open comment on Padrões is carried into the first loop
      expect(p.card(1).notes.single.body, contains('Padrões'));
    });

    test(
      'review revises open sections and turns approved ones into amendments',
      () async {
        final plan = push().plan!;
        store.comment(
          plan,
          'arquitetura',
          'Arquitetura',
          'Falta a DLQ no fluxo',
        );
        final before = plan.section('arquitetura').digest;
        store.requestPlanReview(plan);
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        // Arquitetura was approved: untouched, request became an amendment.
        expect(plan.section('arquitetura').digest, before);
        expect(plan.amendments.single, contains('Falta a DLQ'));
        // Padrões was open: revised and the thread resolved.
        final padroes = plan.threadsOn('padroes').single;
        expect(padroes.resolved, isTrue);
        expect(plan.section('padroes').blocks.last, isA<TextBlock>());
        expect(plan.version, 2);
      },
    );

    test('the plan has a deploy section and a deploy loop gated on your OK', () {
      final plan = push().plan!;
      expect(plan.sections.map((s) => s.id), contains('deploy'));
      final deploy = plan.proposedCards.last;
      expect(deploy.dependsOn, [2, 4]);
      final prod = deploy.tasks.last;
      expect(prod.needsOk, isTrue);
      expect(deploy.tasks.where((t) => t.needsOk), [prod]);
    });

    test('replying reopens a resolved thread', () {
      final t = push().plan!.threads.first..resolved = true;
      store.reply(t, 'Na verdade, quero repensar isso');
      expect(t.resolved, isFalse);
      expect(t.awaitingAgent, isTrue);
    });

    test('a new plan is drafted from its sources, then filled', () async {
      final p = store.createPlan('Favoritos', 'Salvar produtos', [
        'https://x.atlassian.net/browse/MOB-1',
        'https://www.figma.com/design/abc',
      ]);
      expect(p.plan!.drafting, isTrue);
      expect(p.plan!.sources.map((s) => s.kind), ['Jira', 'Figma']);
      expect(p.plan!.canStart, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 1900));
      expect(p.plan!.drafting, isFalse);
      expect(p.plan!.proposedCards, hasLength(4));
    });
  });

  test('learn turns your card comments into skill changes, once', () {
    final p = store.projects.first;
    store.addCardNote(
      p.card(3),
      'Sempre rodar o teste de contrato antes do PR',
    );
    expect(store.unlearnedNotes(p), 2); // seeded note + this one
    store.learn(p);
    expect(p.learnings.map((l) => l.skill), everyElement('backend-service'));
    expect(store.unlearnedNotes(p), 0);
    store.learn(p);
    expect(p.learnings, hasLength(2));
  });

  test('card notes are kept on the card', () {
    final c = store.projects.first.card(6);
    store.addCardNote(c, 'Incluir exemplo em curl');
    expect(c.notes.single.body, 'Incluir exemplo em curl');
  });

  test('removing a catalog item takes it out of every session', () {
    final item = store.catalog.firstWhere((i) => i.id == 'code-review');
    store.removeCatalogItem(item);
    expect(
      store.sessions.any((s) => s.appliedItems.contains('code-review')),
      isFalse,
    );
    expect(store.catalog.contains(item), isFalse);
  });
}
