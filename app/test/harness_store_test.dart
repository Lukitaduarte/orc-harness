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
}
