import 'package:flutter/painting.dart';

// The terminal screen as the daemon sends it (orc_protocol::GridSnapshot
// and GridDiff, as JSON). The daemon emulates the terminal; this only keeps
// the cells and applies row diffs.

class TermCell {
  const TermCell(this.text, this.fg, this.bg, this.flags);

  final String text;

  /// null = theme default.
  final Color? fg;
  final Color? bg;
  final int flags;

  static const bold = 1, italic = 2, underline = 4, inverse = 8, dim = 16;
  static const strike = 32, wideSpacer = 64;

  bool has(int flag) => flags & flag != 0;

  factory TermCell.fromJson(Map<String, dynamic> j) => TermCell(
    j['text'] as String? ?? ' ',
    termColor(j['fg']),
    termColor(j['bg']),
    j['flags'] as int? ?? 0,
  );
}

class GridState {
  int cols = 0;
  int rows = 0;
  List<List<TermCell>> lines = [];
  int cursorRow = 0;
  int cursorCol = 0;
  bool cursorVisible = true;

  /// Applies a GridDiff (or a full snapshot, which has every line).
  void apply(Map<String, dynamic> diff) {
    final c = diff['cols'] as int, r = diff['rows'] as int;
    if (c != cols || r != rows) {
      cols = c;
      rows = r;
      lines = List.generate(r, (_) => const []);
    }
    final changed = diff['lines'] as List;
    for (var i = 0; i < changed.length; i++) {
      // GridDiff lines are [row, cells]; GridSnapshot lines are just cells.
      final entry = changed[i];
      final (row, cells) = entry is List && entry.length == 2 && entry[0] is int
          ? (entry[0] as int, entry[1] as List)
          : (i, entry as List);
      if (row < lines.length) {
        lines[row] = [
          for (final cell in cells)
            TermCell.fromJson(cell as Map<String, dynamic>),
        ];
      }
    }
    final cursor = diff['cursor'] as Map<String, dynamic>;
    cursorRow = cursor['row'] as int;
    cursorCol = cursor['col'] as int;
    cursorVisible = cursor['visible'] as bool? ?? true;
  }

  String lineText(int row) => row < lines.length
      ? lines[row].map((c) => c.text).join().trimRight()
      : '';
}

/// xterm's 16 base colors, tuned to read on the zinc theme.
const _ansi = [
  Color(0xFF18181B),
  Color(0xFFEF4444),
  Color(0xFF22C55E),
  Color(0xFFEAB308),
  Color(0xFF3B82F6),
  Color(0xFFA855F7),
  Color(0xFF06B6D4),
  Color(0xFFD4D4D8),
  Color(0xFF52525B),
  Color(0xFFF87171),
  Color(0xFF4ADE80),
  Color(0xFFFACC15),
  Color(0xFF60A5FA),
  Color(0xFFC084FC),
  Color(0xFF22D3EE),
  Color(0xFFFAFAFA),
];

Color? termColor(Object? json) {
  if (json is! Map) return null;
  switch (json['kind']) {
    case 'rgb':
      return Color.fromARGB(
        255,
        json['r'] as int,
        json['g'] as int,
        json['b'] as int,
      );
    case 'indexed':
      final i = json['index'] as int;
      if (i < 16) return _ansi[i];
      if (i < 232) {
        // 6x6x6 color cube.
        const steps = [0, 95, 135, 175, 215, 255];
        final n = i - 16;
        return Color.fromARGB(
          255,
          steps[n ~/ 36],
          steps[(n ~/ 6) % 6],
          steps[n % 6],
        );
      }
      final v = 8 + (i - 232) * 10;
      return Color.fromARGB(255, v, v, v);
    default:
      return null;
  }
}
