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
    Project users() => store.projects.firstWhere((p) => p.id == 'users-pagination');

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
      expect(store.runningCount(p), lessThanOrEqualTo(HarnessStore.maxRunningCards));
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
}
