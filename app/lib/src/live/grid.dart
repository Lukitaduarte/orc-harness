import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart';

// The terminal screen as the daemon sends it (orc_protocol::GridSnapshot
// and GridDiff, as JSON or binary, see orc_protocol::wire). The daemon
// emulates the terminal; this only keeps the cells and applies row diffs.

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

  /// Bumped each time a row changes, so drawing can keep unchanged rows.
  List<int> versions = [];
  int _next = 0;

  void _resize(int c, int r) {
    if (c == cols && r == rows) return;
    cols = c;
    rows = r;
    lines = List.generate(r, (_) => const []);
    versions = List.generate(r, (_) => ++_next);
  }

  void _setRow(int row, List<TermCell> cells) {
    if (row >= lines.length) return;
    lines[row] = cells;
    versions[row] = ++_next;
  }

  /// Applies a GridDiff (or a full snapshot, which has every line).
  void apply(Map<String, dynamic> diff) {
    _resize(diff['cols'] as int, diff['rows'] as int);
    final changed = diff['lines'] as List;
    for (var i = 0; i < changed.length; i++) {
      // GridDiff lines are [row, cells]; GridSnapshot lines are just cells.
      final entry = changed[i];
      final (row, cells) = entry is List && entry.length == 2 && entry[0] is int
          ? (entry[0] as int, entry[1] as List)
          : (i, entry as List);
      _setRow(row, [
        for (final cell in cells)
          TermCell.fromJson(cell as Map<String, dynamic>),
      ]);
    }
    final cursor = diff['cursor'] as Map<String, dynamic>;
    cursorRow = cursor['row'] as int;
    cursorCol = cursor['col'] as int;
    cursorVisible = cursor['visible'] as bool? ?? true;
  }

  /// Applies a binary grid (orc_protocol::wire, after the kind byte).
  /// False when it is malformed (nothing applied then).
  bool applyBinary(Uint8List bytes) {
    final r = _Reader(bytes);
    try {
      if (r.u8() != _wireVersion) return false;
      r.skip(r.u16()); // session id, read by [binaryGridSession]
      final c = r.u16(), rr = r.u16();
      final crow = r.u16(), ccol = r.u16(), visible = r.u8() != 0;
      final changed = <(int, List<TermCell>)>[];
      for (var n = r.u16(); n > 0; n--) {
        final row = r.u16();
        final cells = <TermCell>[];
        for (var runs = r.u16(); runs > 0; runs--) {
          final flags = r.u8();
          final fg = r.color(), bg = r.color();
          final count = r.u16();
          if (r.u8() == 0) {
            for (var i = 0; i < count; i++) {
              cells.add(TermCell(_ascii[r.u8() & 0x7F], fg, bg, flags));
            }
          } else {
            for (var i = 0; i < count; i++) {
              cells.add(TermCell(r.utf8(r.u8()), fg, bg, flags));
            }
          }
        }
        changed.add((row, cells));
      }
      _resize(c, rr);
      for (final (row, cells) in changed) {
        _setRow(row, cells);
      }
      cursorRow = crow;
      cursorCol = ccol;
      cursorVisible = visible;
      return true;
    } on RangeError {
      return false;
    }
  }

  String lineText(int row) => row < lines.length
      ? lines[row].map((c) => c.text).join().trimRight()
      : '';
}

const _wireVersion = 1;

/// Single-character strings for ASCII cells, made once.
final _ascii = List.generate(128, String.fromCharCode);

/// The session a binary grid belongs to, or null if it is not one.
String? binaryGridSession(Uint8List bytes) {
  if (bytes.length < 3 || bytes[0] != _wireVersion) return null;
  final n = bytes[1] | bytes[2] << 8;
  if (bytes.length < 3 + n) return null;
  return utf8.decode(Uint8List.sublistView(bytes, 3, 3 + n));
}

class _Reader {
  _Reader(this.b);

  final Uint8List b;
  int at = 0;

  int u8() => b[at++];
  int u16() {
    final v = b[at] | b[at + 1] << 8;
    at += 2;
    return v;
  }

  void skip(int n) {
    if (at + n > b.length) throw RangeError('grid');
    at += n;
  }

  String utf8(int n) {
    if (at + n > b.length) throw RangeError('grid');
    final s = const Utf8Decoder(
      allowMalformed: true,
    ).convert(Uint8List.sublistView(b, at, at + n));
    at += n;
    return s;
  }

  Color? color() => switch (u8()) {
    0 => null,
    1 => indexedColor(u8()),
    2 => Color.fromARGB(255, u8(), u8(), u8()),
    _ => throw RangeError('cor'),
  };
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
      return indexedColor(json['index'] as int);
    default:
      return null;
  }
}

/// One of the 256 xterm colors (made once each).
Color indexedColor(int i) => _indexed[i & 0xFF];

final _indexed = List<Color>.generate(256, (i) {
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
});
