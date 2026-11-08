import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../i18n.dart';
import '../live/daemon_client.dart';

/// An Android emulator or iOS simulator in a pane: the daemon runs it
/// without a window and streams its screen; taps, drags and typing go back.
/// With no device picked ([id] empty) it lists them.
class EmulatorPane extends StatefulWidget {
  const EmulatorPane({
    super.key,
    required this.daemon,
    required this.id,
    required this.focused,
    required this.onPick,
  });

  final DaemonClient daemon;
  final String id;
  final bool focused;
  final ValueChanged<String> onPick;

  @override
  State<EmulatorPane> createState() => _EmulatorPaneState();
}

class _EmulatorPaneState extends State<EmulatorPane> {
  final _focus = FocusNode();
  Timer? _poll;
  String? _watching;
  Offset? _dragFrom;
  Offset? _dragTo;

  DaemonClient get _d => widget.daemon;

  void _act(Map<String, Object?> action) => _d.emulator(widget.id, action);

  @override
  void initState() {
    super.initState();
    _d.listEmulators();
    _d.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(EmulatorPane old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) _sync();
  }

  @override
  void dispose() {
    _d.removeListener(_sync);
    _poll?.cancel();
    if (_watching != null) _d.emulator(_watching!, {'type': 'unwatch'});
    _focus.dispose();
    super.dispose();
  }

  /// Streams the screen while the device is on; follows a boot until done.
  void _sync() {
    final e = widget.id.isEmpty ? null : _d.emulators[widget.id];
    final want = e?.state == 'on' ? widget.id : null;
    if (want != _watching) {
      if (_watching != null) _d.emulator(_watching!, {'type': 'unwatch'});
      if (want != null) _d.emulator(want, {'type': 'watch'});
      _watching = want;
    }
    final booting = e?.state == 'booting';
    if (booting && _poll == null) {
      _poll = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _d.listEmulators(),
      );
    } else if (!booting) {
      _poll?.cancel();
      _poll = null;
    }
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.handled;
    final key = switch (e.logicalKey) {
      LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter => 'enter',
      LogicalKeyboardKey.backspace => 'backspace',
      LogicalKeyboardKey.escape => 'back',
      _ => null,
    };
    if (key != null) {
      _act({'type': 'key', 'key': key});
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 0x20) {
      _act({'type': 'text', 'text': ch});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _tool(IconData icon, String tip, VoidCallback? onPressed) => Tooltip(
    tooltip: (context) => TooltipContainer(child: Text(tip)),
    child: GhostButton(
      density: ButtonDensity.icon,
      size: ButtonSize.small,
      onPressed: onPressed,
      child: Icon(icon, size: 14),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_d.status != LinkStatus.connected) {
      return Center(child: Text(l10n.devBrowserNoDaemon).small().muted());
    }
    // Frames notify only their emulator, not the whole app.
    return ListenableBuilder(
      listenable: widget.id.isEmpty
          ? _d
          : Listenable.merge([_d, _d.emulatorOf(widget.id)]),
      builder: (context, _) =>
          widget.id.isEmpty ? _picker(context) : _device(context),
    );
  }

  Widget _picker(BuildContext context) {
    final l10n = context.l10n;
    final all = _d.emulators.values.toList()
      ..sort(
        (a, b) => '${a.platform}${a.name}'.compareTo('${b.platform}${b.name}'),
      );
    if (all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _d.emulatorsListed ? l10n.devEmulatorNone : l10n.devLoading,
            textAlign: TextAlign.center,
          ).small().muted(),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(l10n.devEmulatorPick).small().muted(),
        ),
        for (final e in all)
          GhostButton(
            alignment: Alignment.centerLeft,
            onPressed: () => widget.onPick(e.id),
            leading: Icon(
              e.platform == 'ios' ? LucideIcons.apple : LucideIcons.bot,
              size: 14,
            ),
            trailing: Text(_stateLabel(context, e.state)).xSmall().muted(),
            child: Text(e.name, overflow: TextOverflow.ellipsis).small(),
          ),
      ],
    );
  }

  String _stateLabel(BuildContext context, String state) => switch (state) {
    'on' => context.l10n.devEmulatorOn,
    'booting' => context.l10n.devEmulatorBooting,
    _ => context.l10n.devEmulatorOff,
  };

  Widget _device(BuildContext context) {
    final l10n = context.l10n;
    final e = _d.emulatorOf(widget.id);
    final on = e.state == 'on';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              _tool(
                LucideIcons.list,
                l10n.devEmulatorSwitch,
                () => widget.onPick(''),
              ),
              const Gap(4),
              Expanded(
                child: Text(
                  _stateLabel(context, e.state),
                  overflow: TextOverflow.ellipsis,
                ).xSmall().muted(),
              ),
              if (e.platform == 'android')
                _tool(
                  LucideIcons.arrowLeft,
                  l10n.devBack,
                  on ? () => _act({'type': 'key', 'key': 'back'}) : null,
                ),
              _tool(
                LucideIcons.circle,
                l10n.devEmulatorHome,
                on ? () => _act({'type': 'key', 'key': 'home'}) : null,
              ),
              _tool(
                LucideIcons.power,
                on ? l10n.devEmulatorShutdown : l10n.devEmulatorBoot,
                e.state == 'booting'
                    ? null
                    : () => _act({'type': on ? 'shutdown' : 'boot'}),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: switch (e.state) {
            'off' => Center(
              child: PrimaryButton(
                leading: const Icon(LucideIcons.power, size: 14),
                onPressed: () => _act({'type': 'boot'}),
                child: Text(l10n.devEmulatorBoot),
              ),
            ),
            'booting' => Center(
              child: Text(l10n.devEmulatorBooting).small().muted(),
            ),
            _ =>
              e.frame == null
                  ? Center(child: Text(l10n.devLoading).small().muted())
                  : _screen(e),
          },
        ),
      ],
    );
  }

  /// The screen at its own shape, centered; positions go as fractions.
  Widget _screen(LiveEmulator e) {
    return Focus(
      focusNode: _focus,
      autofocus: widget.focused,
      onKeyEvent: _key,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: AspectRatio(
            aspectRatio: e.width / e.height,
            child: LayoutBuilder(
              builder: (context, c) {
                Offset frac(Offset p) => Offset(
                  (p.dx / c.maxWidth).clamp(0, 1),
                  (p.dy / c.maxHeight).clamp(0, 1),
                );
                return GestureDetector(
                  onTapUp: (t) {
                    _focus.requestFocus();
                    final f = frac(t.localPosition);
                    _act({'type': 'tap', 'x': f.dx, 'y': f.dy});
                  },
                  onPanStart: (d) => _dragFrom = _dragTo = d.localPosition,
                  onPanUpdate: (d) => _dragTo = d.localPosition,
                  onPanEnd: (_) {
                    final (a, b) = (_dragFrom, _dragTo);
                    _dragFrom = _dragTo = null;
                    if (a == null || b == null) return;
                    final (fa, fb) = (frac(a), frac(b));
                    _act({
                      'type': 'swipe',
                      'x1': fa.dx,
                      'y1': fa.dy,
                      'x2': fb.dx,
                      'y2': fb.dy,
                    });
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      e.frame!,
                      gaplessPlayback: true,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
