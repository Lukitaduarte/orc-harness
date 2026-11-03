import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import 'format.dart';

/// Usage of the workspace: totals, cost per day and where it went.
/// Live workspaces read the daemon (Claude Code's own metrics); the demo
/// workspaces show generated data.
class AnalyticsView extends StatefulWidget {
  const AnalyticsView(this.store, {super.key});

  final HarnessStore store;

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> {
  int _days = 14;
  bool _table = false;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final today = store.now.toUtc();
    final since = today
        .subtract(Duration(days: _days - 1))
        .toIso8601String()
        .substring(0, 10);
    final rows = store.usageRows
        .where((r) => r.day.compareTo(since) >= 0)
        .toList();

    final days = [
      for (var i = _days - 1; i >= 0; i--)
        today.subtract(Duration(days: i)).toIso8601String().substring(0, 10),
    ];
    final costByDay = {for (final d in days) d: 0.0};
    for (final r in rows) {
      costByDay[r.day] = (costByDay[r.day] ?? 0) + r.costUsd;
    }
    final totalCost = rows.fold(0.0, (a, r) => a + r.costUsd);
    final totalTokens = rows.fold(0, (a, r) => a + r.tokens);
    final byPair = <(String, String), (int, double)>{};
    for (final r in rows) {
      final k = (r.accountId, r.model);
      final v = byPair[k] ?? (0, 0.0);
      byPair[k] = (v.$1 + r.tokens, v.$2 + r.costUsd);
    }
    final breakdown = byPair.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    // Where the money went: each branch of a project is a plan's card.
    final byBranch = <(String?, String?), (int, double)>{};
    for (final r in rows) {
      final k = (r.projectId, r.branch);
      final v = byBranch[k] ?? (0, 0.0);
      byBranch[k] = (v.$1 + r.tokens, v.$2 + r.costUsd);
    }
    final branches = byBranch.entries.toList()
      ..sort((a, b) => b.value.$2.compareTo(a.value.$2));
    final types = (
      rows.fold(0, (a, r) => a + r.input),
      rows.fold(0, (a, r) => a + r.output),
      rows.fold(0, (a, r) => a + r.cacheRead),
      rows.fold(0, (a, r) => a + r.cacheCreation),
    );
    final prompt = types.$1 + types.$3 + types.$4;
    final cacheHit = prompt == 0 ? null : types.$3 / prompt;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Uso · ${store.workspace.name}').large().semiBold(),
                  Text(
                    store.isLive
                        ? 'Métricas do próprio Claude Code (OpenTelemetry), por sessão, conta e modelo.'
                        : 'Dados de demonstração; o workspace Este Mac mostra os reais.',
                  ).xSmall().muted(),
                ],
              ),
            ),
            for (final d in const [7, 14, 30]) ...[
              d == _days
                  ? SecondaryButton(
                      size: ButtonSize.small,
                      onPressed: () {},
                      child: Text('$d dias'),
                    )
                  : GhostButton(
                      size: ButtonSize.small,
                      onPressed: () => setState(() => _days = d),
                      child: Text('$d dias'),
                    ),
              const Gap(4),
            ],
          ],
        ),
        const Gap(16),
        Row(
          children: [
            _Stat('Custo', formatUsd(totalCost)),
            const Gap(12),
            _Stat('Tokens', formatTokens(totalTokens)),
            const Gap(12),
            _Stat('Média por dia', formatUsd(totalCost / _days)),
            const Gap(12),
            _Stat(
              'Lido do cache',
              cacheHit == null ? '—' : '${(cacheHit * 100).round()}%',
            ),
          ],
        ),
        const Gap(16),
        OutlinedContainer(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Tokens por tipo').semiBold(),
              const Gap(12),
              _TokenTypes([
                ('Entrada', types.$1),
                ('Saída', types.$2),
                ('Lido do cache', types.$3),
                ('Escrito no cache', types.$4),
              ]),
            ],
          ),
        ),
        const Gap(16),
        OutlinedContainer(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Custo por dia (US\$)'),
                  ).semiBold(),
                  GhostButton(
                    size: ButtonSize.small,
                    onPressed: () => setState(() => _table = !_table),
                    child: Text(_table ? 'Ver gráfico' : 'Ver tabela'),
                  ),
                ],
              ),
              const Gap(12),
              if (_table)
                _DayTable(costByDay)
              else
                SizedBox(height: 220, child: _CostBars(costByDay)),
            ],
          ),
        ),
        const Gap(16),
        OutlinedContainer(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Por conta e modelo').semiBold(),
              const Gap(10),
              _row(['Conta', 'Modelo', 'Tokens', 'Custo'], head: true),
              const Divider(),
              if (breakdown.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Nenhum uso registrado no período.'),
                ).small().muted()
              else
                for (final e in breakdown)
                  _row([
                    e.key.$1,
                    e.key.$2,
                    formatTokens(e.value.$1),
                    formatUsd(e.value.$2),
                  ]),
            ],
          ),
        ),
        const Gap(16),
        OutlinedContainer(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Por projeto e branch (cards)').semiBold(),
              const Gap(10),
              _row(['Projeto', 'Branch', 'Tokens', 'Custo'], head: true),
              const Divider(),
              for (final e in branches)
                _row([
                  e.key.$1 ?? 'sessões soltas',
                  e.key.$2 ?? '—',
                  formatTokens(e.value.$1),
                  formatUsd(e.value.$2),
                ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(List<String> cells, {bool head = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        for (final (i, c) in cells.indexed)
          Expanded(
            flex: i < 2 ? 3 : 2,
            child: Text(
              c,
              textAlign: i < 2 ? TextAlign.left : TextAlign.right,
            ).small().let((t) => head ? t.xSmall().semiBold().muted() : t),
          ),
      ],
    ),
  );
}

extension on Widget {
  Widget let(Widget Function(Widget) f) => f(this);
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: OutlinedContainer(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label).xSmall().muted(),
          const Gap(4),
          Text(value).x2Large().semiBold(),
        ],
      ),
    ),
  );
}

class _DayTable extends StatelessWidget {
  const _DayTable(this.costByDay);

  final Map<String, double> costByDay;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final MapEntry(:key, :value) in costByDay.entries.toList().reversed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(_dayLabel(key)).small()),
              Text(formatUsd(value)).small(),
            ],
          ),
        ),
    ],
  );
}

String _dayLabel(String day) =>
    '${day.substring(8, 10)}/${day.substring(5, 7)}';

/// One series of columns: rounded tops, 2px gaps, recessive grid, a
/// tooltip per bar on hover.
class _CostBars extends StatefulWidget {
  const _CostBars(this.costByDay);

  final Map<String, double> costByDay;

  @override
  State<_CostBars> createState() => _CostBarsState();
}

class _CostBarsState extends State<_CostBars> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = widget.costByDay.entries.toList();
    final maxValue = entries.fold(0.0, (a, e) => e.value > a ? e.value : a);
    final top = _niceCeil(maxValue);
    return LayoutBuilder(
      builder: (context, c) {
        const left = 44.0, bottom = 22.0;
        final plotW = c.maxWidth - left;
        final plotH = c.maxHeight - bottom;
        final slot = plotW / entries.length;
        return MouseRegion(
          onHover: (e) {
            final i = ((e.localPosition.dx - left) / slot).floor();
            setState(() => _hover = i >= 0 && i < entries.length ? i : null);
          },
          onExit: (_) => setState(() => _hover = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _BarsPainter(
                  values: [for (final e in entries) e.value],
                  labels: [for (final e in entries) _dayLabel(e.key)],
                  top: top,
                  hover: _hover,
                  bar: scheme.chart1,
                  grid: scheme.border,
                  ink: scheme.mutedForeground,
                  style: DefaultTextStyle.of(
                    context,
                  ).style.copyWith(fontSize: 10.5),
                ),
              ),
              if (_hover != null)
                Positioned(
                  left: (left + slot * _hover! + slot / 2 - 60).clamp(
                    0,
                    c.maxWidth - 120,
                  ),
                  top: (plotH - (entries[_hover!].value / top) * plotH - 46)
                      .clamp(0, plotH),
                  child: IgnorePointer(
                    child: Container(
                      width: 120,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.popover,
                        border: Border.all(color: scheme.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _dayLabel(entries[_hover!].key),
                          ).xSmall().muted(),
                          Text(
                            formatUsd(entries[_hover!].value),
                          ).small().semiBold(),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 1, 2 or 5 times a power of ten, at or above `v`.
double _niceCeil(double v) {
  if (v <= 0) return 1;
  var p = 1.0;
  while (p * 10 <= v) {
    p *= 10;
  }
  while (p > v) {
    p /= 10;
  }
  for (final m in const [1, 2, 5, 10]) {
    if (p * m >= v) return p * m;
  }
  return p * 10;
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.labels,
    required this.top,
    required this.hover,
    required this.bar,
    required this.grid,
    required this.ink,
    required this.style,
  });

  final List<double> values;
  final List<String> labels;
  final double top;
  final int? hover;
  final Color bar;
  final Color grid;
  final Color ink;
  final TextStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, bottom = 22.0;
    final plotW = size.width - left;
    final plotH = size.height - bottom;
    final slot = plotW / values.length;

    // Recessive grid with three value lines.
    for (var i = 0; i <= 2; i++) {
      final v = top * i / 2;
      final y = plotH - plotH * i / 2;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width, y),
        Paint()..color = grid,
      );
      final tp = TextPainter(
        text: TextSpan(
          // Same precision on every tick: decimals only for small scales.
          text: '\$${v.toStringAsFixed(top < 2 ? 2 : 0)}',
          style: style.copyWith(color: ink),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - tp.width - 6, y - tp.height / 2));
    }

    final width = (slot - 2).clamp(2.0, 28.0);
    // Label at most ~8 days so they never collide.
    final every = (values.length / 8).ceil();
    for (var i = 0; i < values.length; i++) {
      final cx = left + slot * i + slot / 2;
      final h = plotH * (values[i] / top);
      if (h > 0) {
        final r = Rect.fromLTWH(cx - width / 2, plotH - h, width, h);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            r,
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()
            ..color = hover == null || hover == i
                ? bar
                : bar.withValues(alpha: 0.45),
        );
      }
      if (i % every == 0 || i == values.length - 1) {
        final tp = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: style.copyWith(color: ink),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, plotH + 6));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.hover != hover || old.bar != bar;
}

/// Share of each token type as one segmented bar, labeled in a legend with
/// the numbers (identity never by color alone). Colors: the dataviz
/// reference palette, validated for both modes.
class _TokenTypes extends StatelessWidget {
  const _TokenTypes(this.parts);

  final List<(String, int)> parts;

  static const _light = [
    Color(0xFF2A78D6),
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
    Color(0xFFEDA100),
  ];
  static const _dark = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = scheme.brightness == Brightness.dark ? _dark : _light;
    final total = parts.fold(0, (a, p) => a + p.$2);
    if (total == 0) {
      return const Text('Nenhum token no período.').small().muted();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 12,
          child: Row(
            children: [
              for (final (i, p) in parts.indexed)
                if (p.$2 > 0)
                  Expanded(
                    flex: math.max(1, (p.$2 * 1000 / total).round()),
                    child: Padding(
                      // 2px surface gap between segments.
                      padding: EdgeInsets.only(
                        right: i == parts.length - 1 ? 0 : 2,
                      ),
                      child: Tooltip(
                        tooltip: (context) => TooltipContainer(
                          child: Text('${p.$1}: ${formatTokens(p.$2)}'),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: colors[i],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        const Gap(10),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (final (i, p) in parts.indexed)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors[i],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Gap(6),
                  Text(
                    '${p.$1} · ${formatTokens(p.$2)} · ${(p.$2 * 100 / total).toStringAsFixed(p.$2 * 100 / total < 1 ? 1 : 0)}%',
                  ).xSmall(),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
