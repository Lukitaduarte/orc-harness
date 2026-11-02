import 'model.dart';

/// Reads the subset of Mermaid that plans use and turns it into the native
/// diagram blocks. Returns null for anything it does not understand, so the
/// caller can show the source as code instead.
PlanBlock? parseMermaid(String source, {String caption = ''}) {
  final lines = source
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('%%'))
      .toList();
  if (lines.isEmpty) return null;
  final head = lines.first.split(RegExp(r'\s+'));
  return switch (head.first) {
    'flowchart' || 'graph' => _flowchart(
      lines.skip(1),
      vertical: head.length < 2 || !['LR', 'RL'].contains(head[1]),
      caption: caption,
    ),
    'sequenceDiagram' => _sequence(lines.skip(1), caption: caption),
    _ => null,
  };
}

// A node reference with an optional shape: A, A[x], A(x), A([x]), A[(x)],
// A{x}, A{{x}}, A[[x]], A>x], optionally followed by :::class.
final _nodeRef = RegExp(
  r'^([\w-]+)\s*(\[\(.*?\)\]|\(\[.*?\]\)|\[\[.*?\]\]|\{\{.*?\}\}|\[.*?\]|\(.*?\)|\{.*?\}|>.*?\])?(?::::([\w-]+))?',
);

// Edge operators: -->, --- , -.->, ==>, with |label| or inline "-- label -->".
final _edgeOp = RegExp(
  r'^\s*(?:(-{2,3}>|-{3}|-\.+->|={2,3}>)\s*(?:\|([^|]*)\|)?|--\s+(.+?)\s+-->|-\.\s+(.+?)\s+\.->|==\s+(.+?)\s+==>)\s*',
);

FlowchartBlock? _flowchart(
  Iterable<String> lines, {
  required bool vertical,
  required String caption,
}) {
  final nodes = <String, _Node>{};
  final order = <String>[];
  final edges = <DiagramEdge>[];
  final groups = <DiagramGroup>[];
  final groupStack = <String>[];
  final classes = <String, Set<String>>{};

  void touch(String id, String? shape, String? cls) {
    final n = nodes.putIfAbsent(id, () {
      order.add(id);
      return _Node(id);
    });
    if (groupStack.isNotEmpty) n.group ??= groupStack.last;
    if (shape != null) n.applyShape(shape);
    if (cls != null) n.classes.add(cls);
  }

  for (final line in lines) {
    if (line == 'end') {
      if (groupStack.isNotEmpty) groupStack.removeLast();
      continue;
    }
    if (line.startsWith('subgraph ')) {
      final m = RegExp(
        r'^subgraph\s+([\w-]+)\s*(?:\[\s*"?(.*?)"?\s*\])?\s*$',
      ).firstMatch(line);
      final rest = line.substring(9).trim();
      final id = m?.group(1) ?? _slug(rest);
      final label = m?.group(2) ?? rest.replaceAll('"', '');
      groups.add(DiagramGroup(id, label));
      groupStack.add(id);
      continue;
    }
    if (line.startsWith('class ')) {
      final parts = line.substring(6).trim().split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        for (final id in parts.first.split(',')) {
          classes.putIfAbsent(id, () => {}).add(parts[1]);
        }
      }
      continue;
    }
    if (line.startsWith('direction ') ||
        line.startsWith('classDef ') ||
        line.startsWith('style ') ||
        line.startsWith('linkStyle ') ||
        line.startsWith('click ')) {
      continue;
    }

    // A chain: node (edge node)*
    var rest = line;
    var m = _nodeRef.firstMatch(rest);
    if (m == null) return null;
    touch(m.group(1)!, m.group(2), m.group(3));
    var from = m.group(1)!;
    rest = rest.substring(m.end);
    while (rest.trim().isNotEmpty) {
      final op = _edgeOp.firstMatch(rest);
      if (op == null) return null;
      final arrow =
          op.group(1) ??
          (op.group(3) != null
              ? '-->'
              : op.group(4) != null
              ? '-.->'
              : '==>');
      final label =
          (op.group(2) ?? op.group(3) ?? op.group(4) ?? op.group(5) ?? '')
              .trim();
      rest = rest.substring(op.end);
      final target = _nodeRef.firstMatch(rest);
      if (target == null) return null;
      touch(target.group(1)!, target.group(2), target.group(3));
      edges.add(
        DiagramEdge(
          from,
          target.group(1)!,
          label: _clean(label),
          failure: arrow.startsWith('-.'),
          taken: arrow.startsWith('='),
        ),
      );
      from = target.group(1)!;
      rest = rest.substring(target.end);
    }
  }
  if (order.isEmpty) return null;
  for (final MapEntry(:key, :value) in classes.entries) {
    nodes[key]?.classes.addAll(value);
  }
  return FlowchartBlock(
    caption: caption,
    vertical: vertical,
    groups: groups,
    edges: edges,
    nodes: [for (final id in order) nodes[id]!.toDiagramNode()],
  );
}

class _Node {
  _Node(this.id) : label = id;

  final String id;
  String label;
  String detail = '';
  NodeKind kind = NodeKind.component;
  String? group;
  final classes = <String>{};

  void applyShape(String shape) {
    String inner(int cut) => shape.substring(cut, shape.length - cut);
    if (shape.startsWith('[(')) {
      kind = NodeKind.store;
      _setText(inner(2));
    } else if (shape.startsWith('{{') ||
        shape.startsWith('[[') ||
        shape.startsWith('([')) {
      _setText(inner(2));
    } else if (shape.startsWith('{')) {
      kind = NodeKind.decision;
      _setText(inner(1));
    } else if (shape.startsWith('>')) {
      _setText(shape.substring(1, shape.length - 1));
    } else {
      _setText(inner(1));
    }
  }

  /// "Label<br/>detail" → label + detail; quotes dropped.
  void _setText(String raw) {
    final parts = raw
        .replaceAll('"', '')
        .split(RegExp(r'<br\s*/?>|\\n'))
        .map((p) => _clean(p.trim()))
        .toList();
    label = parts.first;
    detail = parts.skip(1).join(' · ');
  }

  DiagramNode toDiagramNode() => DiagramNode(
    id,
    label,
    detail: detail,
    kind: classes.contains('external') ? NodeKind.external : kind,
    group: group,
    isNew: classes.contains('new') || classes.contains('novo'),
  );
}

SequenceBlock? _sequence(Iterable<String> lines, {required String caption}) {
  final participants = <String>[];
  final alias = <String, String>{};
  final messages = <SequenceMessage>[];
  final frames = <SequenceFrame>[];
  final open = <(String, int)>[];

  String who(String id) {
    final name = alias[id] ?? id;
    if (!participants.contains(name)) participants.add(name);
    return name;
  }

  final participantLine = RegExp(
    r'^(?:participant|actor)\s+([^\s]+)(?:\s+as\s+(.+))?$',
  );
  final messageLine = RegExp(
    r'^([^\s:]+?)\s*(-{1,2}>>|-{1,2}>|-{1,2}x|-{1,2}\))\s*([^\s:]+?)\s*:\s*(.*)$',
  );

  for (final line in lines) {
    final p = participantLine.firstMatch(line);
    if (p != null) {
      final label = p.group(2)?.trim() ?? p.group(1)!;
      alias[p.group(1)!] = label;
      who(p.group(1)!);
      continue;
    }
    final block = RegExp(
      r'^(alt|opt|loop|par|critical|break)\b\s*(.*)$',
    ).firstMatch(line);
    if (block != null) {
      open.add((
        '${block.group(1)}  ${block.group(2)}'.trim(),
        messages.length,
      ));
      continue;
    }
    if (line.startsWith('else') || line.startsWith('and')) continue;
    if (line == 'end') {
      if (open.isNotEmpty) {
        final (label, first) = open.removeLast();
        if (messages.length > first) {
          frames.add(SequenceFrame(label, first, messages.length - 1));
        }
      }
      continue;
    }
    final m = messageLine.firstMatch(line);
    if (m != null) {
      messages.add(
        SequenceMessage(
          who(m.group(1)!),
          who(m.group(3)!),
          _clean(m.group(4)!.trim()),
          reply: m.group(2)!.startsWith('--'),
        ),
      );
      continue;
    }
    // Notes, activations, autonumber and the rest are ignored.
  }
  if (participants.isEmpty || messages.isEmpty) return null;
  return SequenceBlock(
    caption: caption,
    participants: participants,
    messages: messages,
    frames: frames,
  );
}

String _clean(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .replaceAll('"', '');

String _slug(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
