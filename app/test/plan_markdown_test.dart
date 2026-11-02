import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/mermaid.dart';
import 'package:orc_harness/src/model.dart';
import 'package:orc_harness/src/plan_markdown.dart';
import 'package:orc_harness/src/plan_templates.dart';

/// A ```mermaid block that fell back to code means the parser missed it.
bool unreadDiagram(PlanBlock b) =>
    b is CodeBlock &&
    RegExp(r'^\s*(flowchart|graph|sequenceDiagram)').hasMatch(b.code);

void main() {
  group('example plan', () {
    final parsed = parsePlanMarkdown(pushPlanMarkdown);
    final plan = parsed.plan;

    test('frontmatter, title and summary', () {
      expect(parsed.title, 'Notificações push');
      expect(parsed.repo, 'work/mobile');
      expect(plan.sources.map((s) => s.kind), ['Jira', 'Confluence', 'Figma']);
      expect(plan.summary, startsWith('Notificações push para iOS'));
    });

    test('sections keep their ids, explicit or slugged', () {
      expect(plan.sections.map((s) => s.id), [
        'fontes',
        'checklist',
        'escopo',
        'arquitetura',
        'padroes',
        'ds',
        'estrutura',
        'codigo',
        'observabilidade',
        'testes',
        'deploy',
        'execucao',
        'entregas',
        'pendencias',
      ]);
    });

    test('every diagram is read natively', () {
      final blocks = plan.sections.expand((s) => s.blocks);
      expect(blocks.where(unreadDiagram), isEmpty);
      final arch = plan.section('arquitetura').blocks;
      final flow = arch.whereType<FlowchartBlock>().single;
      expect(flow.groups.map((g) => g.id), [
        'pedidos',
        'infra',
        'notifier',
        'app',
      ]);
      final outbox = flow.nodes.firstWhere((n) => n.id == 'outbox');
      expect(outbox.kind, NodeKind.store);
      expect(outbox.isNew, isTrue);
      expect(outbox.detail, 'tabela transacional');
      expect(flow.edges.firstWhere((e) => e.to == 'dlq').failure, isTrue);
      final seq = arch.whereType<SequenceBlock>().single;
      expect(seq.participants, [
        'Pedidos',
        'Fila',
        'Notifier',
        'FCM/APNs',
        'App',
      ]);
      expect(seq.messages, hasLength(9));
      expect(seq.frames.single.first, 6);
      expect(seq.frames.single.last, 8);
    });

    test('loops come from the YAML block', () {
      expect(plan.proposedCards, hasLength(5));
      expect(plan.proposedCards[2].title, 'App: permissão e recebimento');
      final deploy = plan.proposedCards.last;
      expect(deploy.dependsOn, [2, 4]);
      expect(deploy.tasks.last.needsOk, isTrue);
      expect(deploy.tasks.last.dependsOn, ['T18']);
    });

    test('tables drop the separator row', () {
      final t = plan.section('checklist').blocks.whereType<TableBlock>().single;
      expect(t.headers, ['Item', 'Resposta', 'Origem']);
      expect(t.rows, hasLength(5));
    });
  });

  test('every template parses, with instructions, loops and diagrams', () {
    for (final t in seedTemplates) {
      final plan = parsePlanMarkdown(t.markdown).plan;
      expect(plan.sections, isNotEmpty, reason: t.id);
      expect(plan.proposedCards, isNotEmpty, reason: t.id);
      expect(
        plan.sections.any((s) => s.instruction.isNotEmpty),
        isTrue,
        reason: t.id,
      );
      expect(
        plan.sections.expand((s) => s.blocks).where(unreadDiagram),
        isEmpty,
        reason: t.id,
      );
    }
    final blank = parsePlanMarkdown(blankTemplate).plan;
    expect(blank.sections.map((s) => s.id), [
      'fontes',
      'arquitetura',
      'execucao',
    ]);
  });

  group('mermaid', () {
    test('chains, inline labels and classes', () {
      final f =
          parseMermaid('''
flowchart LR
  a[A] --> b[B] --> c[C]
  a -- texto --> c
  a -.-> d
  class d external
''')
              as FlowchartBlock;
      expect(f.vertical, isFalse);
      expect(f.edges.map((e) => '${e.from}${e.to}'), ['ab', 'bc', 'ac', 'ad']);
      expect(f.edges[2].label, 'texto');
      expect(f.edges[3].failure, isTrue);
      expect(f.nodes.firstWhere((n) => n.id == 'd').kind, NodeKind.external);
    });

    test('anything else falls back', () {
      expect(parseMermaid('pie title X\n "a" : 1'), isNull);
      expect(parseMermaid('flowchart TB\n  a ~~~ ???'), isNull);
    });
  });
}
