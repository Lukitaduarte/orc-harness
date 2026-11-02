import 'package:yaml/yaml.dart';

import 'mermaid.dart';
import 'model.dart';

/// A plan read from markdown.
class ParsedPlan {
  const ParsedPlan(this.title, this.repo, this.plan);

  final String title;
  final String repo;
  final Plan plan;
}

/// Reads a plan written in markdown, so plans and plan templates are fully
/// customizable files. The format:
///
/// - optional YAML frontmatter: `repo`, `sources` (list of links);
/// - `# Title`, then the summary paragraph;
/// - each `## Section` is an approvable section (`## Title {#id}` sets the
///   id); an HTML comment inside it is the instruction the planning agent
///   follows for that section;
/// - paragraphs, lists, tables and fenced code become the matching blocks;
/// - ` ```mermaid ` with `flowchart` or `sequenceDiagram` becomes a native
///   diagram (text after the language is the caption);
/// - ` ```loops ` holds the execution loops in YAML.
ParsedPlan parsePlanMarkdown(String source) {
  var text = source.replaceAll('\r\n', '\n');
  var repo = '';
  final sources = <PlanSource>[];

  if (text.startsWith('---\n')) {
    final end = text.indexOf('\n---', 4);
    if (end > 0) {
      final front = loadYaml(text.substring(4, end));
      if (front is YamlMap) {
        repo = '${front['repo'] ?? ''}';
        for (final s in (front['sources'] as YamlList? ?? YamlList())) {
          sources.add(PlanSource.fromUrl('$s'));
        }
      }
      text = text.substring(text.indexOf('\n', end + 1) + 1);
    }
  }

  var title = '';
  final summary = <String>[];
  final sections = <PlanSection>[];
  final loops = <TaskCard>[];
  String? sectionTitle;
  String? sectionId;
  final body = <String>[];

  void closeSection() {
    final title = sectionTitle;
    if (title == null) return;
    final (blocks, instruction) = _blocks(body, loops);
    sections.add(
      PlanSection(sectionId ?? _id(title), title, blocks)
        ..instruction = instruction,
    );
    body.clear();
  }

  var inFence = false;
  for (final line in text.split('\n')) {
    if (line.trimLeft().startsWith('```')) inFence = !inFence;
    if (!inFence && line.startsWith('# ') && title.isEmpty) {
      title = _inline(line.substring(2).trim());
    } else if (!inFence && line.startsWith('## ')) {
      closeSection();
      final m = RegExp(
        r'^##\s+(.*?)\s*(?:\{#([\w-]+)\})?\s*$',
      ).firstMatch(line)!;
      sectionTitle = _inline(m.group(1)!);
      sectionId = m.group(2);
    } else if (sectionTitle == null) {
      if (line.trim().isNotEmpty && !line.startsWith('#')) {
        summary.add(_inline(line.trim()));
      }
    } else {
      body.add(line);
    }
  }
  closeSection();

  return ParsedPlan(
    title,
    repo,
    Plan(
      summary: summary.join(' '),
      sources: sources,
      sections: sections,
      proposedCards: loops,
    ),
  );
}

(List<PlanBlock>, String) _blocks(List<String> lines, List<TaskCard> loops) {
  final blocks = <PlanBlock>[];
  final instruction = <String>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isNotEmpty) {
      blocks.add(TextBlock(paragraph.join(' ')));
      paragraph.clear();
    }
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final t = line.trim();

    if (t.startsWith('<!--')) {
      flushParagraph();
      final buf = StringBuffer();
      var cur = t.substring(4);
      while (!cur.contains('-->') && i + 1 < lines.length) {
        buf.writeln(cur);
        cur = lines[++i].trim();
      }
      buf.write(cur.substring(0, cur.indexOf('-->')));
      instruction.add(
        buf
            .toString()
            .replaceFirst(RegExp(r'^\s*(prompt|instrução):\s*'), '')
            .trim(),
      );
      i++;
      continue;
    }

    if (t.startsWith('```')) {
      flushParagraph();
      final info = t.substring(3).trim();
      final lang = info.split(RegExp(r'\s+')).first;
      final caption = info.substring(lang.length).trim();
      final code = <String>[];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        code.add(lines[i]);
        i++;
      }
      i++; // closing fence
      final src = code.join('\n');
      if (lang == 'mermaid') {
        blocks.add(
          parseMermaid(src, caption: caption) ?? CodeBlock(caption, src),
        );
      } else if (lang == 'loops') {
        final parsed = _loops(src, loops.length);
        loops.addAll(parsed);
        blocks.add(LoopsBlock(parsed));
      } else {
        blocks.add(CodeBlock(caption, src));
      }
      continue;
    }

    if (t.startsWith('|')) {
      flushParagraph();
      final rows = <List<String>>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        final cells = lines[i].trim();
        final inner = cells.substring(
          1,
          cells.endsWith('|') ? cells.length - 1 : cells.length,
        );
        final row = inner.split('|').map((c) => _inline(c.trim())).toList();
        // The |---|---| separator row is not data.
        if (!row.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c))) {
          rows.add(row);
        }
        i++;
      }
      if (rows.isNotEmpty) {
        blocks.add(TableBlock(rows.first, rows.skip(1).toList()));
      }
      continue;
    }

    final item = RegExp(r'^\s*(?:[-*+]|\d+\.)\s+(?:\[[ xX]\]\s+)?(.*)$');
    if (item.hasMatch(line)) {
      flushParagraph();
      final items = <String>[];
      while (i < lines.length) {
        final m = item.firstMatch(lines[i]);
        if (m != null) {
          items.add(_inline(m.group(1)!));
        } else if (lines[i].startsWith('  ') &&
            lines[i].trim().isNotEmpty &&
            items.isNotEmpty) {
          items[items.length - 1] += ' ${_inline(lines[i].trim())}';
        } else {
          break;
        }
        i++;
      }
      blocks.add(BulletsBlock(items));
      continue;
    }

    if (t.isEmpty) {
      flushParagraph();
    } else {
      paragraph.add(_inline(t.replaceFirst(RegExp(r'^#{3,6}\s+'), '')));
    }
    i++;
  }
  flushParagraph();
  return (blocks, instruction.join('\n'));
}

/// The ```loops block: a YAML list of loops, numbered in order.
List<TaskCard> _loops(String yaml, int offset) {
  final doc = loadYaml(yaml);
  if (doc is! YamlList) return [];
  List<String> strings(Object? v) =>
      v is YamlList ? [for (final x in v) '$x'] : const [];
  return [
    for (var i = 0; i < doc.length; i++)
      if (doc[i] case final YamlMap l)
        TaskCard(
          number: offset + i + 1,
          title: '${l['title'] ?? 'Loop ${offset + i + 1}'}',
          type: '${l['type'] ?? 'feat'}',
          model: '${l['model'] ?? 'sonnet'}',
          dependsOn: [
            for (final d in (l['depends_on'] as YamlList? ?? YamlList()))
              int.parse('$d'),
          ],
          description: '${l['description'] ?? ''}',
          criteria: strings(l['criteria']),
          tasks: [
            for (final t in (l['tasks'] as YamlList? ?? YamlList()))
              if (t case final YamlMap task)
                CardTask(
                  '${task['id']}',
                  '${task['title']}',
                  skill: '${task['skill'] ?? ''}',
                  model: '${task['model'] ?? 'sonnet'}',
                  group: (task['group'] as int?) ?? 1,
                  dependsOn: strings(task['after']),
                  needsOk: task['needs_ok'] == true,
                ),
          ],
        ),
  ];
}

/// Inline markdown to plain text: emphasis, code spans and links.
String _inline(String s) => s
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!)
    .replaceAll(RegExp(r'\*\*|__'), '')
    .replaceAll('`', '');

String _id(String title) => foldAccents(
  title,
).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
