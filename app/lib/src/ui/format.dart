import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../i18n.dart';
import '../model.dart';

String formatDuration(Duration d) {
  if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
  if (d.inHours > 0) {
    return '${d.inHours}h${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  }
  if (d.inMinutes > 0) return '${d.inMinutes}min';
  return '${d.inSeconds}s';
}

String formatTokens(int t) {
  String one(double v, String unit) =>
      '${v.toStringAsFixed(1).replaceAll('.', ',')}$unit';
  if (t >= 1000000) return one(t / 1000000, 'M');
  if (t >= 1000) return one(t / 1000, 'k');
  return '$t';
}

String formatUsd(double v) => '\$${v.toStringAsFixed(2)}';

/// Green below 70%, amber from 70%, red from 90%.
Color quotaColor(BuildContext context, double percent) {
  if (percent >= 90) return Theme.of(context).colorScheme.destructive;
  if (percent >= 70) return Colors.amber;
  return Colors.emerald;
}

Color sessionStateColor(BuildContext context, SessionState s) => switch (s) {
  SessionState.running => Colors.emerald,
  SessionState.waitingInput => Colors.amber,
  SessionState.starting => Colors.blue,
  SessionState.idle => Theme.of(context).colorScheme.mutedForeground,
};

String sessionStateLabel(SessionState s) => switch (s) {
  SessionState.running => l10n.toolsSessionRunning,
  SessionState.waitingInput => l10n.toolsSessionWaiting,
  SessionState.starting => l10n.toolsSessionStarting,
  SessionState.idle => l10n.toolsSessionIdle,
};

class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
