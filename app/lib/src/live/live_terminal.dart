import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../i18n.dart';
import 'grid.dart';

/// A session's terminal, live: draws the daemon's grid, sends keys as
/// input and reports the size it has room for.
class LiveTerminal extends StatefulWidget {
  const LiveTerminal({
    required this.grid,
    required this.onInput,
    required this.onResize,
    this.focused = false,
    super.key,
  });

  final GridState? grid;
  final ValueChanged<String> onInput;
  final void Function(int cols, int rows) onResize;
  final bool focused;

  @override
  State<LiveTerminal> createState() => _LiveTerminalState();
}

class _LiveTerminalState extends State<LiveTerminal> {
  final _focus = FocusNode();
  final _cache = _RowCache();
  (int, int)? _reported;

  @override
  void initState() {
    super.initState();
    // A session opened in the focused pane takes the keyboard once.
    if (widget.focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void didUpdateWidget(LiveTerminal old) {
    super.didUpdateWidget(old);
    // Only when this pane becomes the focused one: rebuilds happen every
    // second (the quota clock) and must not pull the keyboard away from a
    // dialog or text field you are typing in.
    if (widget.focused && !old.focused && !_focus.hasFocus) {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _cache.clear(null);
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final data = keyToTerminal(e, HardwareKeyboard.instance);
    if (data == null) return KeyEventResult.ignored;
    widget.onInput(data);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).typography.mono.copyWith(fontSize: 12.5, height: 1.25);
    final cell = _cellSize(style);
    return LayoutBuilder(
      builder: (context, c) {
        // Tell the daemon how many cells fit; it resizes the PTY.
        final cols = (c.maxWidth - 16) ~/ cell.width;
        final rows = (c.maxHeight - 16) ~/ cell.height;
        if (cols > 0 && rows > 0 && _reported != (cols, rows)) {
          _reported = (cols, rows);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => widget.onResize(cols, rows),
          );
        }
        return Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: GestureDetector(
            onTap: _focus.requestFocus,
            child: Container(
              color: Theme.of(context).colorScheme.background,
              padding: const EdgeInsets.all(8),
              child: widget.grid == null
                  ? Center(child: Text(context.l10n.devConnectingTerminal))
                  : CustomPaint(
                      painter: _GridPainter(
                        widget.grid!,
                        style,
                        cell,
                        Theme.of(context).colorScheme,
                        _cache,
                      ),
                      size: Size.infinite,
                    ),
            ),
          ),
        );
      },
    );
  }
}

Size _cellSize(TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: 'M', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return Size(tp.width, tp.height);
}

/// Rows recorded so far (tests check unchanged rows are not redrawn).
@visibleForTesting
int debugRowsRecorded = 0;

/// What drawing keeps between frames: each row as a recorded picture
/// (redrawn only when the row's version changes), and laid-out text runs
/// (most runs repeat: prompts, borders, the status line).
class _RowCache {
  Object? key;
  final rows = <int, (int, ui.Picture)>{};
  final runs = <String, TextPainter>{}; // insertion-ordered: LRU
  static const maxRuns = 2048;

  /// Drops everything (the font, colors or cell size changed).
  void clear(Object? newKey) {
    key = newKey;
    for (final (_, p) in rows.values) {
      p.dispose();
    }
    rows.clear();
    for (final t in runs.values) {
      t.dispose();
    }
    runs.clear();
  }

  TextPainter run(String key, InlineSpan Function() span) {
    final hit = runs.remove(key);
    if (hit != null) return runs[key] = hit; // most recent last
    if (runs.length >= maxRuns) runs.remove(runs.keys.first)?.dispose();
    return runs[key] = TextPainter(
      text: span(),
      textDirection: TextDirection.ltr,
    )..layout();
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.grid, this.style, this.cell, this.scheme, this.cache);

  final GridState grid;
  final TextStyle style;
  final Size cell;
  final ColorScheme scheme;
  final _RowCache cache;

  @override
  void paint(Canvas canvas, Size size) {
    final key = (style, cell, scheme.foreground, scheme.background);
    if (cache.key != key) cache.clear(key);
    final rows = grid.lines.length;
    cache.rows.removeWhere((r, entry) {
      final gone = r >= rows;
      if (gone) entry.$2.dispose();
      return gone;
    });
    for (var r = 0; r < rows; r++) {
      final version = r < grid.versions.length ? grid.versions[r] : -1;
      var entry = cache.rows[r];
      if (entry == null || entry.$1 != version) {
        entry?.$2.dispose();
        entry = (version, _record(grid.lines[r]));
        cache.rows[r] = entry;
      }
      canvas.save();
      canvas.translate(0, r * cell.height);
      canvas.drawPicture(entry.$2);
      canvas.restore();
    }
    if (grid.cursorVisible) {
      canvas.drawRect(
        Rect.fromLTWH(
          grid.cursorCol * cell.width,
          grid.cursorRow * cell.height,
          cell.width,
          cell.height,
        ),
        Paint()..color = scheme.foreground.withValues(alpha: 0.55),
      );
    }
  }

  /// One row, at y = 0: backgrounds, then runs of same-looking cells.
  ui.Picture _record(List<TermCell> line) {
    debugRowsRecorded++;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    var c = 0;
    while (c < line.length) {
      final first = line[c];
      var end = c + 1;
      while (end < line.length && _sameLook(line[end], first)) {
        end++;
      }
      var fg = first.fg ?? scheme.foreground;
      var bg = first.bg;
      if (first.has(TermCell.inverse)) {
        (fg, bg) = (bg ?? scheme.background, fg);
      }
      final rect = Rect.fromLTWH(
        c * cell.width,
        0,
        (end - c) * cell.width,
        cell.height,
      );
      if (bg != null) canvas.drawRect(rect, Paint()..color = bg);
      final buf = StringBuffer();
      for (var i = c; i < end; i++) {
        if (!line[i].has(TermCell.wideSpacer)) buf.write(line[i].text);
      }
      final text = buf.toString();
      if (text.trim().isNotEmpty) {
        final color = first.has(TermCell.dim) ? fg.withValues(alpha: 0.6) : fg;
        cache
            .run(
              '${first.flags}|${color.toARGB32()}|$text',
              () => TextSpan(
                text: text,
                style: style.copyWith(
                  color: color,
                  fontWeight: first.has(TermCell.bold)
                      ? FontWeight.w700
                      : FontWeight.w400,
                  fontStyle: first.has(TermCell.italic)
                      ? FontStyle.italic
                      : FontStyle.normal,
                  decoration: TextDecoration.combine([
                    if (first.has(TermCell.underline)) TextDecoration.underline,
                    if (first.has(TermCell.strike)) TextDecoration.lineThrough,
                  ]),
                ),
              ),
            )
            .paint(canvas, rect.topLeft);
      }
      c = end;
    }
    return recorder.endRecording();
  }

  static bool _sameLook(TermCell a, TermCell b) =>
      a.fg == b.fg && a.bg == b.bg && a.flags == b.flags;

  // The grid object is mutated in place; unchanged rows are pictures.
  @override
  bool shouldRepaint(_GridPainter old) => true;
}

/// Translates a key press into the bytes a terminal program expects.
String? keyToTerminal(KeyEvent e, HardwareKeyboard kb) {
  final k = e.logicalKey;
  if (kb.isControlPressed && k.keyLabel.length == 1) {
    final code = k.keyLabel.toUpperCase().codeUnitAt(0);
    if (code >= 64 && code <= 95) return String.fromCharCode(code - 64);
  }
  const special = {
    'Enter': '\r',
    'Backspace': '\x7f',
    'Tab': '\t',
    'Escape': '\x1b',
    'Arrow Up': '\x1b[A',
    'Arrow Down': '\x1b[B',
    'Arrow Right': '\x1b[C',
    'Arrow Left': '\x1b[D',
    'Home': '\x1b[H',
    'End': '\x1b[F',
    'Delete': '\x1b[3~',
    'Page Up': '\x1b[5~',
    'Page Down': '\x1b[6~',
  };
  final s = special[k.keyLabel];
  if (s != null) {
    // Shift+Tab is how Claude Code cycles modes.
    if (k == LogicalKeyboardKey.tab && kb.isShiftPressed) return '\x1b[Z';
    return s;
  }
  if (kb.isMetaPressed) return null; // ⌘ shortcuts belong to the app
  return e.character;
}
