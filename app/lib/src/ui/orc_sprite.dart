import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';

/// The harness's orc: original 16×16 pixel art (a homage to the old
/// real-time-strategy peons, drawn here, not taken from any game), idling
/// and blinking, with an optional line in a speech bubble.
class OrcSprite extends StatefulWidget {
  const OrcSprite({super.key, this.scale = 4, this.says});

  /// Screen pixels per sprite pixel.
  final double scale;

  /// A line in a speech bubble beside it ("Work, work.").
  final String? says;

  @override
  State<OrcSprite> createState() => _OrcSpriteState();
}

/// Palette: outline, hair, skin, skin shade, eyes, tusks, leather, dark
/// leather. '.' is transparent.
const _palette = {
  'k': Color(0xFF1A1410),
  'h': Color(0xFF2B1D12),
  'g': Color(0xFF5B9C2A),
  'G': Color(0xFF3F7420),
  'y': Color(0xFFFFD23F),
  'w': Color(0xFFEFE6C8),
  'b': Color(0xFF8A5A2B),
  'B': Color(0xFF5E3B1A),
};

/// One frame, 16 rows of 16.
const _idle = [
  '................',
  '.....kkkkkk.....',
  '....khhhhhhk....',
  '.k.kggggggggk.k.',
  '.kgkgyggggygkgk.',
  '..kgggggggggggk.',
  '...kgGGGGGGgk...',
  '...kgwgggwgk....',
  '....kgggggk.....',
  '...kbbkkkkbbk...',
  '..kbBbgggbBbk...',
  '.kgkbBbgbBbkgk..',
  '.kgkbbbbbbbkgk..',
  '..kkBBBBBBBkk...',
  '...kGGk.kGGk....',
  '...kkkk.kkkk....',
];

/// The same with eyes shut.
final _blink = [
  for (final (i, row) in _idle.indexed) i == 4 ? row.replaceAll('y', 'G') : row,
];

class _OrcSpriteState extends State<OrcSprite> {
  late final Timer _timer;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    // Breathes every beat; blinks now and then.
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() => _tick++);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _tick % 9 == 8 ? _blink : _idle;
    final bob = _tick.isOdd ? widget.scale : 0.0;
    final sprite = SizedBox(
      width: 16 * widget.scale,
      height: 17 * widget.scale,
      child: CustomPaint(painter: _Pixels(frame, widget.scale, bob)),
    );
    final says = widget.says;
    if (says == null) return sprite;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        sprite,
        const Gap(8),
        // A square, pixel-ish bubble.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.card,
            border: Border.all(color: scheme.foreground, width: 2),
          ),
          child: Text(says).mono().small().semiBold(),
        ),
      ],
    );
  }
}

class _Pixels extends CustomPainter {
  _Pixels(this.rows, this.scale, this.dy);

  final List<String> rows;
  final double scale;
  final double dy;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (final (y, row) in rows.indexed) {
      for (var x = 0; x < row.length; x++) {
        final c = _palette[row[x]];
        if (c == null) continue;
        paint.color = c;
        canvas.drawRect(
          Rect.fromLTWH(x * scale, y * scale + scale - dy, scale, scale),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Pixels old) => old.rows != rows || old.dy != dy;
}
