import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/model.dart';
import 'package:orc_harness/src/ui/diagrams.dart';

const chart = FlowchartBlock(
  groups: [DiagramGroup('g', 'Grupo')],
  nodes: [
    DiagramNode('a', 'A'),
    DiagramNode('b', 'B', group: 'g'),
    DiagramNode('c', 'C', group: 'g'),
    DiagramNode('d', 'D'),
  ],
  edges: [
    DiagramEdge('a', 'b'),
    DiagramEdge('a', 'c'),
    DiagramEdge('b', 'd'),
    DiagramEdge('c', 'd'),
    DiagramEdge('d', 'a', failure: true), // cycle back to the start
  ],
);

void main() {
  final layout = layoutFlowchart(chart, (_) => 48);

  test('nodes are ranked by longest path, ignoring the back edge', () {
    final a = layout.nodes['a']!,
        b = layout.nodes['b']!,
        d = layout.nodes['d']!;
    expect(b.top, greaterThan(a.bottom));
    expect(d.top, greaterThan(b.bottom));
    expect(layout.nodes['c']!.top, b.top); // same layer
  });

  test('no two nodes overlap', () {
    final rects = layout.nodes.values.toList();
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse);
      }
    }
  });

  test('a group encloses its members and the canvas encloses everything', () {
    final g = layout.groups['g']!;
    expect(g.contains(layout.nodes['b']!.center), isTrue);
    expect(g.contains(layout.nodes['c']!.center), isTrue);
    for (final r in [...layout.nodes.values, g]) {
      expect(r.right, lessThanOrEqualTo(layout.size.width));
      expect(r.bottom, lessThanOrEqualTo(layout.size.height));
    }
  });

  test('left-to-right puts layers in columns', () {
    const lr = FlowchartBlock(
      vertical: false,
      nodes: [DiagramNode('x', 'X'), DiagramNode('y', 'Y')],
      edges: [DiagramEdge('x', 'y')],
    );
    final l = layoutFlowchart(lr, (_) => 40);
    expect(l.nodes['y']!.left, greaterThan(l.nodes['x']!.right));
  });
}
