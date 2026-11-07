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

class _GridPainter extends CustomPainter {
  _GridPainter(this.grid, this.style, this.cell, this.scheme);

  final GridState grid;
  final TextStyle style;
  final Size cell;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    for (var r = 0; r < grid.lines.length; r++) {
      final line = grid.lines[r];
      final y = r * cell.height;
      // Runs of cells with the same look are drawn as one span.
      var c = 0;
      while (c < line.length) {
        final first = line[c];
        var end = c + 1;
        while (end < line.length && _sameLook(line[end], first)) {
          end++;
        }
        final run = line.sublist(c, end);
        var fg = first.fg ?? scheme.foreground;
        var bg = first.bg;
        if (first.has(TermCell.inverse)) {
          (fg, bg) = (bg ?? scheme.background, fg);
        }
        final rect = Rect.fromLTWH(
          c * cell.width,
          y,
          (end - c) * cell.width,
          cell.height,
        );
        if (bg != null) canvas.drawRect(rect, Paint()..color = bg);
        final text = run
            .where((x) => !x.has(TermCell.wideSpacer))
            .map((x) => x.text)
            .join();
        if (text.trim().isNotEmpty) {
          TextPainter(
              text: TextSpan(
                text: text,
                style: style.copyWith(
                  color: first.has(TermCell.dim)
                      ? fg.withValues(alpha: 0.6)
                      : fg,
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
              textDirection: TextDirection.ltr,
            )
            ..layout()
            ..paint(canvas, rect.topLeft);
        }
        c = end;
      }
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

  static bool _sameLook(TermCell a, TermCell b) =>
      a.fg == b.fg && a.bg == b.bg && a.flags == b.flags;

  // The grid object is mutated in place; repaint on every rebuild.
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
