import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../model.dart';

// Native renderers for the plan's diagrams. The agent sends nodes, edges and
// messages; layout and drawing happen here, in the app's theme.

const _nodeWidth = 176.0;
const _nodeGap = 28.0;
const _layerGap = 64.0;
const _pad = 16.0;

/// Positions computed for a flowchart.
class FlowLayout {
  const FlowLayout(this.nodes, this.groups, this.size);

  final Map<String, Rect> nodes;
  final Map<String, Rect> groups;
  final Size size;
}

/// Layered layout: rank by longest path (back edges ignored), order each
/// layer by the barycenter of its predecessors, keep a group's nodes
/// together, then place layers top-down (or left-right).
FlowLayout layoutFlowchart(
  FlowchartBlock b,
  double Function(DiagramNode) heightOf,
) {
  final ids = [for (final n in b.nodes) n.id];
  final byId = {for (final n in b.nodes) n.id: n};
  final edges = b.edges
      .where((e) => byId.containsKey(e.from) && byId.containsKey(e.to))
      .toList();

  // Back edges (cycles) are found by DFS and left out of the ranking.
  final back = <DiagramEdge>{};
  final state = <String, int>{}; // 1 visiting, 2 done
  void dfs(String id) {
    state[id] = 1;
    for (final e in edges.where((e) => e.from == id)) {
      if (state[e.to] == 1) {
        back.add(e);
      } else if (state[e.to] == null) {
        dfs(e.to);
      }
    }
    state[id] = 2;
  }

  for (final id in ids) {
    if (state[id] == null) dfs(id);
  }
  final forward = edges.where((e) => !back.contains(e)).toList();

  final rank = <String, int>{};
  int rankOf(String id) => rank[id] ??= forward
      .where((e) => e.to == id)
      .map((e) => rankOf(e.from) + 1)
      .fold(0, math.max);
  for (final id in ids) {
    rankOf(id);
  }

  final layerCount = rank.values.fold(0, math.max) + 1;
  final layers = [
    for (var r = 0; r < layerCount; r++)
      [
        for (final id in ids)
          if (rank[id] == r) id,
      ],
  ];

  // Barycenter ordering, one pass down.
  for (var r = 1; r < layerCount; r++) {
    final prev = layers[r - 1];
    double center(String id) {
      final preds = forward
          .where((e) => e.to == id && rank[e.from] == r - 1)
          .map((e) => prev.indexOf(e.from))
          .toList();
      return preds.isEmpty
          ? layers[r].indexOf(id).toDouble()
          : preds.reduce((a, c) => a + c) / preds.length;
    }

    final centers = {for (final id in layers[r]) id: center(id)};
    layers[r].sort((a, c) => centers[a]!.compareTo(centers[c]!));
  }
  // Keep each group's nodes side by side.
  final groupOrder = [for (final g in b.groups) g.id];
  int groupIndex(String id) {
    final g = byId[id]!.group;
    return g == null ? groupOrder.length : groupOrder.indexOf(g);
  }

  for (final layer in layers) {
    final order = {for (var i = 0; i < layer.length; i++) layer[i]: i};
    layer.sort((a, c) {
      final g = groupIndex(a).compareTo(groupIndex(c));
      return g != 0 ? g : order[a]!.compareTo(order[c]!);
    });
  }

  final heights = {for (final n in b.nodes) n.id: heightOf(n)};
  final rects = <String, Rect>{};
  final groupTop = b.groups.isEmpty ? 0.0 : 22.0;
  if (b.vertical) {
    final widths = [
      for (final l in layers) l.length * _nodeWidth + (l.length - 1) * _nodeGap,
    ];
    final maxWidth = widths.fold(0.0, math.max);
    var y = _pad + groupTop;
    for (var r = 0; r < layerCount; r++) {
      final layerHeight = layers[r]
          .map((id) => heights[id]!)
          .fold(0.0, math.max);
      var x = _pad + (maxWidth - widths[r]) / 2;
      for (final id in layers[r]) {
        final h = heights[id]!;
        rects[id] = Rect.fromLTWH(x, y + (layerHeight - h) / 2, _nodeWidth, h);
        x += _nodeWidth + _nodeGap;
      }
      y += layerHeight + _layerGap;
    }
  } else {
    final columnHeights = [
      for (final l in layers)
        l.map((id) => heights[id]!).fold(0.0, (a, h) => a + h) +
            (l.length - 1) * _nodeGap,
    ];
    final maxHeight = columnHeights.fold(0.0, math.max);
    var x = _pad;
    for (var r = 0; r < layerCount; r++) {
      var y = _pad + groupTop + (maxHeight - columnHeights[r]) / 2;
      for (final id in layers[r]) {
        rects[id] = Rect.fromLTWH(x, y, _nodeWidth, heights[id]!);
        y += heights[id]! + _nodeGap;
      }
      x += _nodeWidth + _layerGap + 24;
    }
  }

  final groups = <String, Rect>{};
  for (final g in b.groups) {
    final members = [
      for (final n in b.nodes)
        if (n.group == g.id) rects[n.id]!,
    ];
    if (members.isEmpty) continue;
    final box = members.reduce((a, c) => a.expandToInclude(c));
    groups[g.id] = Rect.fromLTRB(
      box.left - 10,
      box.top - 26,
      box.right + 10,
      box.bottom + 10,
    );
  }

  final all = [...rects.values, ...groups.values];
  final right = all.map((r) => r.right).fold(0.0, math.max) + _pad;
  final bottom = all.map((r) => r.bottom).fold(0.0, math.max) + _pad;
  return FlowLayout(rects, groups, Size(right, bottom));
}

class _Palette {
  _Palette(BuildContext context)
    : base = DefaultTextStyle.of(context).style,
      scheme = Theme.of(context).colorScheme;

  final TextStyle base;
  final ColorScheme scheme;

  TextStyle get label => base.copyWith(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: scheme.foreground,
    height: 1.25,
  );
  TextStyle get detail => base.copyWith(
    fontSize: 11.5,
    fontWeight: FontWeight.w400,
    color: scheme.mutedForeground,
    height: 1.3,
  );
  TextStyle get small => detail.copyWith(fontSize: 11);
}

TextPainter _text(
  String s,
  TextStyle style,
  double maxWidth, {
  TextAlign align = TextAlign.left,
}) => TextPainter(
  text: TextSpan(text: s, style: style),
  textDirection: TextDirection.ltr,
  textAlign: align,
)..layout(maxWidth: maxWidth);

/// Flowchart with groups, labelled edges, failure branches and new nodes.
class FlowchartView extends StatelessWidget {
  const FlowchartView(this.block, {super.key});

  final FlowchartBlock block;

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);
    final layout = layoutFlowchart(block, (n) {
      final inner = _nodeWidth - 24;
      var h = 20 + _text(n.label, palette.label, inner).height;
      if (n.detail.isNotEmpty) {
        h += 2 + _text(n.detail, palette.detail, inner).height;
      }
      return n.kind == NodeKind.decision ? math.max(h + 16, 64) : h;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (block.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(block.caption).xSmall().semiBold().muted(),
          ),
        _Canvas(
          size: layout.size,
          painter: _FlowPainter(block, layout, palette),
        ),
      ],
    );
  }
}

/// Fits the drawing to the column: shrinks down to 70%, then scrolls.
class _Canvas extends StatelessWidget {
  const _Canvas({required this.size, required this.painter});

  final Size size;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final scale = math.min(1.0, math.max(0.7, c.maxWidth / size.width));
      final drawing = SizedBox(
        width: size.width * scale,
        height: size.height * scale,
        child: FittedBox(
          child: SizedBox.fromSize(
            size: size,
            child: CustomPaint(painter: painter),
          ),
        ),
      );
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.muted.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
        ),
        child: size.width * scale > c.maxWidth
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: drawing,
              )
            : Center(child: drawing),
      );
    },
  );
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(this.block, this.layout, this.p);

  final FlowchartBlock block;
  final FlowLayout layout;
  final _Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    final s = p.scheme;
    for (final g in block.groups) {
      final r = layout.groups[g.id];
      if (r == null) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(10)),
        Paint()..color = s.muted.withValues(alpha: 0.45),
      );
      _dashedRRect(
        canvas,
        RRect.fromRectAndRadius(r, const Radius.circular(10)),
        s.border,
      );
      _text(
        g.label.toUpperCase(),
        p.small.copyWith(fontWeight: FontWeight.w600),
        r.width,
      ).paint(canvas, r.topLeft + const Offset(10, 6));
    }

    final byId = {for (final n in block.nodes) n.id: n};
    for (final e in block.edges) {
      final a = layout.nodes[e.from];
      final b = layout.nodes[e.to];
      if (a == null || b == null) continue;
      final color = e.failure
          ? s.destructive
          : e.taken
          ? s.primary
          : s.mutedForeground;
      _edge(canvas, a, b, e, color);
    }

    for (final n in block.nodes) {
      final r = layout.nodes[n.id]!;
      _node(canvas, r, byId[n.id]!);
    }
  }

  void _node(Canvas canvas, Rect r, DiagramNode n) {
    final s = p.scheme;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = n.isNew ? 1.6 : 1
      ..color = n.isNew ? s.primary : s.border;
    final fill = Paint()..color = n.kind == NodeKind.store ? s.muted : s.card;
    switch (n.kind) {
      case NodeKind.decision:
        final path = Path()
          ..moveTo(r.center.dx, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.center.dx, r.bottom)
          ..lineTo(r.left, r.center.dy)
          ..close();
        canvas
          ..drawPath(path, fill)
          ..drawPath(path, border);
      case NodeKind.store:
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(14));
        canvas
          ..drawRRect(rr, fill)
          ..drawRRect(rr, border)
          ..drawLine(
            Offset(r.left + 8, r.top + 6),
            Offset(r.right - 8, r.top + 6),
            border..strokeWidth = 1,
          );
      case NodeKind.external:
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(8));
        canvas.drawRRect(rr, fill);
        _dashedRRect(canvas, rr, s.mutedForeground);
      case NodeKind.component:
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(8));
        canvas
          ..drawRRect(rr, fill)
          ..drawRRect(rr, border);
    }

    final inner = r.width - 24;
    final label = _text(n.label, p.label, inner, align: TextAlign.center);
    final detail = n.detail.isEmpty
        ? null
        : _text(n.detail, p.detail, inner, align: TextAlign.center);
    final total = label.height + (detail == null ? 0 : detail.height + 2);
    var y = r.center.dy - total / 2;
    label.paint(canvas, Offset(r.left + 12 + (inner - label.width) / 2, y));
    if (detail != null) {
      y += label.height + 2;
      detail.paint(canvas, Offset(r.left + 12 + (inner - detail.width) / 2, y));
    }
    if (n.isNew) {
      // A small pill sitting on the top border, clear of the label.
      final tag = _text(
        'novo',
        p.small.copyWith(
          fontSize: 10,
          color: p.scheme.primaryForeground,
          fontWeight: FontWeight.w600,
        ),
        40,
      );
      final pill = Rect.fromLTWH(
        r.right - tag.width - 18,
        r.top - tag.height / 2 - 2,
        tag.width + 10,
        tag.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pill, const Radius.circular(8)),
        Paint()..color = p.scheme.primary,
      );
      tag.paint(canvas, Offset(pill.left + 5, pill.top + 2));
    }
  }

  void _edge(Canvas canvas, Rect a, Rect b, DiagramEdge e, Color color) {
    final vertical = block.vertical;
    final forward = vertical ? b.top > a.bottom - 1 : b.left > a.right - 1;
    late Offset p0, p3, c1, c2;
    if (forward) {
      if (vertical) {
        p0 = a.bottomCenter;
        p3 = b.topCenter;
        final d = (p3.dy - p0.dy) / 2;
        c1 = p0 + Offset(0, d);
        c2 = p3 - Offset(0, d);
      } else {
        p0 = a.centerRight;
        p3 = b.centerLeft;
        final d = (p3.dx - p0.dx) / 2;
        c1 = p0 + Offset(d, 0);
        c2 = p3 - Offset(d, 0);
      }
    } else {
      // Back or same-layer edge: loop around the right (or bottom) side.
      if (vertical) {
        p0 = a.centerRight;
        p3 = b.centerRight;
        final out = math.max(a.right, b.right) + 48;
        c1 = Offset(out, p0.dy);
        c2 = Offset(out, p3.dy);
      } else {
        p0 = a.bottomCenter;
        p3 = b.bottomCenter;
        final out = math.max(a.bottom, b.bottom) + 40;
        c1 = Offset(p0.dx, out);
        c2 = Offset(p3.dx, out);
      }
    }
    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p3.dx, p3.dy);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = e.taken ? 1.8 : 1.2
      ..color = color;
    if (e.failure) {
      _dashedPath(canvas, path, stroke);
    } else {
      canvas.drawPath(path, stroke);
    }
    // Arrowhead along the curve's end tangent.
    final dir = (p3 - c2);
    final angle = math.atan2(dir.dy, dir.dx);
    const len = 8.0;
    final head = Path()
      ..moveTo(p3.dx, p3.dy)
      ..lineTo(
        p3.dx - len * math.cos(angle - 0.45),
        p3.dy - len * math.sin(angle - 0.45),
      )
      ..lineTo(
        p3.dx - len * math.cos(angle + 0.45),
        p3.dy - len * math.sin(angle + 0.45),
      )
      ..close();
    canvas.drawPath(head, Paint()..color = color);

    if (e.label.isNotEmpty) {
      final mid = _bezier(p0, c1, c2, p3, 0.5);
      final t = _text(
        e.label,
        p.small.copyWith(color: color),
        140,
        align: TextAlign.center,
      );
      final box = Rect.fromCenter(
        center: mid,
        width: t.width + 10,
        height: t.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(4)),
        Paint()..color = p.scheme.background,
      );
      t.paint(canvas, Offset(box.left + 5, box.top + 2));
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) =>
      old.block != block || old.p.scheme != p.scheme;
}

/// Sequence diagram: participants, lifelines, messages, replies and frames.
class SequenceView extends StatelessWidget {
  const SequenceView(this.block, {super.key});

  final SequenceBlock block;

  @override
  Widget build(BuildContext context) {
    final palette = _Palette(context);
    final minCol = block.participants
        .map((pt) => _text(pt, palette.label, 400).width + 40)
        .fold(130.0, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (block.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(block.caption).xSmall().semiBold().muted(),
          ),
        LayoutBuilder(
          builder: (context, c) {
            // Columns share the available width, never narrower than a label.
            final n = block.participants.length;
            final col = math.max(minCol, (c.maxWidth - 2 * _pad) / n);
            final size = Size(
              col * n + 2 * _pad,
              _pad + _headerHeight + 30 + block.messages.length * _rowHeight,
            );
            return _Canvas(
              size: size,
              painter: _SequencePainter(block, palette, col),
            );
          },
        ),
      ],
    );
  }
}

const _headerHeight = 34.0;
const _rowHeight = 40.0;

class _SequencePainter extends CustomPainter {
  _SequencePainter(this.block, this.p, this.col);

  final SequenceBlock block;
  final _Palette p;
  final double col;

  double _x(String participant) =>
      _pad + col * block.participants.indexOf(participant) + col / 2;
  double _y(int message) => _pad + _headerHeight + 30 + message * _rowHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final s = p.scheme;
    final bottom = size.height - _pad / 2;

    for (final f in block.frames) {
      final r = Rect.fromLTRB(
        _pad / 2,
        _y(f.first) - 26,
        size.width - _pad / 2,
        _y(f.last) + 12,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(6)),
        Paint()..color = s.destructive.withValues(alpha: 0.06),
      );
      _dashedRRect(
        canvas,
        RRect.fromRectAndRadius(r, const Radius.circular(6)),
        s.destructive.withValues(alpha: 0.6),
      );
      final t = _text(
        f.label,
        p.small.copyWith(color: s.destructive, fontWeight: FontWeight.w600),
        200,
      );
      t.paint(canvas, r.topLeft + const Offset(8, 4));
    }

    for (final pt in block.participants) {
      final x = _x(pt);
      _dashedLine(
        canvas,
        Offset(x, _pad + _headerHeight),
        Offset(x, bottom),
        Paint()
          ..color = s.border
          ..strokeWidth = 1,
      );
      final label = _text(pt, p.label, col - 16, align: TextAlign.center);
      final box = Rect.fromCenter(
        center: Offset(x, _pad + _headerHeight / 2),
        width: math.min(col - 16, label.width + 24),
        height: _headerHeight,
      );
      final rr = RRect.fromRectAndRadius(box, const Radius.circular(8));
      canvas
        ..drawRRect(rr, Paint()..color = s.card)
        ..drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = s.border,
        );
      label.paint(
        canvas,
        Offset(
          box.center.dx - label.width / 2,
          box.center.dy - label.height / 2,
        ),
      );
    }

    for (var i = 0; i < block.messages.length; i++) {
      final m = block.messages[i];
      final y = _y(i);
      final x1 = _x(m.from);
      final x2 = _x(m.to);
      final color = m.reply ? s.mutedForeground : s.foreground;
      final stroke = Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      final label = _text(
        m.label,
        p.detail.copyWith(fontSize: 12.5, color: color),
        col * 1.6,
        align: TextAlign.center,
      );
      if (x1 == x2) {
        final path = Path()
          ..moveTo(x1, y - 8)
          ..lineTo(x1 + 36, y - 8)
          ..lineTo(x1 + 36, y + 6)
          ..lineTo(x1 + 4, y + 6);
        canvas.drawPath(path, stroke);
        _arrow(canvas, Offset(x1, y + 6), math.pi, color);
        label.paint(canvas, Offset(x1 + 42, y - label.height / 2 - 1));
        continue;
      }
      final from = Offset(x1, y);
      final to = Offset(x2 + (x2 > x1 ? -2 : 2), y);
      if (m.reply) {
        _dashedLine(canvas, from, to, stroke);
      } else {
        canvas.drawLine(from, to, stroke);
      }
      _arrow(canvas, to, x2 > x1 ? 0 : math.pi, color);
      label.paint(
        canvas,
        Offset((x1 + x2) / 2 - label.width / 2, y - label.height - 3),
      );
    }
  }

  void _arrow(Canvas canvas, Offset tip, double angle, Color color) {
    const len = 8.0;
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - len * math.cos(angle - 0.45),
        tip.dy - len * math.sin(angle - 0.45),
      )
      ..lineTo(
        tip.dx - len * math.cos(angle + 0.45),
        tip.dy - len * math.sin(angle + 0.45),
      )
      ..close();
    canvas.drawPath(head, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SequencePainter old) =>
      old.block != block || old.p.scheme != p.scheme;
}

Offset _bezier(Offset a, Offset b, Offset c, Offset d, double t) {
  final u = 1 - t;
  return a * (u * u * u) +
      b * (3 * u * u * t) +
      c * (3 * u * t * t) +
      d * (t * t * t);
}

void _dashedPath(
  Canvas canvas,
  Path path,
  Paint paint, {
  double dash = 5,
  double gap = 4,
}) {
  for (final ui.PathMetric m in path.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      d += dash + gap;
    }
  }
}

void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) => _dashedPath(
  canvas,
  Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy),
  paint,
);

void _dashedRRect(Canvas canvas, RRect r, Color color) => _dashedPath(
  canvas,
  Path()..addRRect(r),
  Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = color,
);
