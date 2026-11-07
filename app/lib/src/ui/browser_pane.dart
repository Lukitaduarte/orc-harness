import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../i18n.dart';
import '../live/daemon_client.dart';

/// A workspace browser in a pane: the daemon's headless Chrome as a stream
/// of frames, driven with the mouse and keyboard. Agents with the
/// workspace browser in their profile drive the same one.
class BrowserPane extends StatefulWidget {
  const BrowserPane({
    super.key,
    required this.daemon,
    required this.profile,
    required this.focused,
  });

  final DaemonClient daemon;
  final String profile;
  final bool focused;

  @override
  State<BrowserPane> createState() => _BrowserPaneState();
}

class _BrowserPaneState extends State<BrowserPane> {
  final _url = TextEditingController();
  final _urlFocus = FocusNode();
  final _pageFocus = FocusNode();
  Size _size = Size.zero;
  Timer? _resize;
  DateTime _lastMove = DateTime(0);

  LiveBrowser get _b => widget.daemon.browserOf(widget.profile);

  void _send(Map<String, Object?> action) =>
      widget.daemon.browser(widget.profile, action);

  @override
  void initState() {
    super.initState();
    _b.addListener(_onBrowser);
    _url.text = _b.url;
  }

  @override
  void dispose() {
    _b.removeListener(_onBrowser);
    _resize?.cancel();
    _url.dispose();
    _urlFocus.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  void _onBrowser() {
    // The address follows the page unless you are typing one.
    if (!_urlFocus.hasFocus && _url.text != _b.url) _url.text = _b.url;
  }

  /// The page takes the pane's size (debounced while dragging splits).
  void _sized(Size s) {
    if (s == _size || s.isEmpty) return;
    _size = s;
    _resize?.cancel();
    _resize = Timer(const Duration(milliseconds: 250), () {
      _send({
        'action': 'resize',
        'width': s.width.round(),
        'height': s.height.round(),
      });
    });
  }

  /// Pane position to page position (the frame may lag a resize).
  Offset _page(Offset local) {
    final b = _b;
    if (b.width == 0 || _size.isEmpty) return local;
    return Offset(
      local.dx * b.width / _size.width,
      local.dy * b.height / _size.height,
    );
  }

  void _mouse(
    String type,
    Offset local, {
    String button = 'none',
    int clicks = 0,
    Offset delta = Offset.zero,
  }) {
    final p = _page(local);
    _send({
      'action': 'input',
      'event': {
        'kind': 'mouse',
        'type': type,
        'x': p.dx,
        'y': p.dy,
        'button': button,
        'clickCount': clicks,
        'deltaX': delta.dx,
        'deltaY': delta.dy,
      },
    });
  }

  static String _button(int buttons) => switch (buttons) {
    kSecondaryMouseButton => 'right',
    kMiddleMouseButton => 'middle',
    _ => 'left',
  };

  static final _named = {
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.numpadEnter: 'Enter',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.tab: 'Tab',
    LogicalKeyboardKey.escape: 'Escape',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
    LogicalKeyboardKey.arrowRight: 'ArrowRight',
    LogicalKeyboardKey.arrowUp: 'ArrowUp',
    LogicalKeyboardKey.arrowDown: 'ArrowDown',
    LogicalKeyboardKey.home: 'Home',
    LogicalKeyboardKey.end: 'End',
    LogicalKeyboardKey.pageUp: 'PageUp',
    LogicalKeyboardKey.pageDown: 'PageDown',
  };

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.handled;
    final hw = HardwareKeyboard.instance;
    if (hw.isMetaPressed || hw.isControlPressed) {
      if (e.logicalKey == LogicalKeyboardKey.keyV) {
        Clipboard.getData(Clipboard.kTextPlain).then((d) {
          final t = d?.text;
          if (t != null && t.isNotEmpty) {
            _send({
              'action': 'input',
              'event': {'kind': 'text', 'text': t},
            });
          }
        });
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final named = _named[e.logicalKey];
    if (named != null) {
      _send({
        'action': 'input',
        'event': {
          'kind': 'key',
          'key': named,
          'modifiers': hw.isShiftPressed ? 8 : 0,
        },
      });
      return KeyEventResult.handled;
    }
    final ch = e.character;
    if (ch != null && ch.isNotEmpty && ch.codeUnitAt(0) >= 0x20) {
      _send({
        'action': 'input',
        'event': {'kind': 'text', 'text': ch},
      });
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
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _b,
      builder: (context, _) {
        final b = _b;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  _tool(
                    LucideIcons.arrowLeft,
                    context.l10n.devBack,
                    b.open ? () => _send({'action': 'back'}) : null,
                  ),
                  _tool(
                    LucideIcons.arrowRight,
                    context.l10n.devForward,
                    b.open ? () => _send({'action': 'forward'}) : null,
                  ),
                  _tool(
                    LucideIcons.rotateCw,
                    context.l10n.devReload,
                    b.open ? () => _send({'action': 'reload'}) : null,
                  ),
                  const Gap(4),
                  Expanded(
                    child: TextField(
                      controller: _url,
                      focusNode: _urlFocus,
                      placeholder: Text(context.l10n.devAddress),
                      style: const TextStyle(fontSize: 12),
                      onSubmitted: (u) {
                        if (u.trim().isEmpty) return;
                        _send({'action': 'open', 'url': u.trim()});
                        _pageFocus.requestFocus();
                      },
                    ),
                  ),
                  const Gap(4),
                  _tool(
                    LucideIcons.power,
                    context.l10n.devCloseBrowser,
                    b.open ? () => _send({'action': 'close'}) : null,
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: widget.daemon.status != LinkStatus.connected
                  // Nothing reaches a browser without the daemon.
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          context.l10n.devBrowserNoDaemon,
                          textAlign: TextAlign.center,
                        ).small().muted(),
                      ),
                    )
                  : !b.open
                  ? Center(
                      child: PrimaryButton(
                        leading: const Icon(LucideIcons.globe, size: 14),
                        onPressed: () => _send({'action': 'open', 'url': null}),
                        child: Text(context.l10n.devOpenWorkspaceBrowser),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, c) {
                        _sized(c.biggest);
                        return Focus(
                          focusNode: _pageFocus,
                          onKeyEvent: _key,
                          child: Listener(
                            onPointerDown: (e) {
                              _pageFocus.requestFocus();
                              _mouse(
                                'mousePressed',
                                e.localPosition,
                                button: _button(e.buttons),
                                clicks: 1,
                              );
                            },
                            onPointerUp: (e) => _mouse(
                              'mouseReleased',
                              e.localPosition,
                              button: 'left',
                              clicks: 1,
                            ),
                            onPointerHover: (e) {
                              // ~30 moves a second is plenty for hover.
                              final now = DateTime.now();
                              if (now.difference(_lastMove).inMilliseconds <
                                  33) {
                                return;
                              }
                              _lastMove = now;
                              _mouse('mouseMoved', e.localPosition);
                            },
                            onPointerMove: (e) => _mouse(
                              'mouseMoved',
                              e.localPosition,
                              button: _button(e.buttons),
                            ),
                            onPointerSignal: (e) {
                              if (e is PointerScrollEvent) {
                                _mouse(
                                  'mouseWheel',
                                  e.localPosition,
                                  delta: e.scrollDelta,
                                );
                              }
                            },
                            child: Container(
                              color: scheme.background,
                              child: b.frame == null
                                  ? Center(child: Text(context.l10n.devLoading))
                                  : Image.memory(
                                      b.frame!,
                                      gaplessPlayback: true,
                                      fit: BoxFit.fill,
                                      filterQuality: FilterQuality.medium,
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
