import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Typing into a session from a phone: the soft keyboard cannot type into
/// the terminal itself, so text goes from this field, plus the keys the
/// Claude Code TUI needs (Esc, Tab, arrows, Ctrl-C).
class LiveInputBar extends StatefulWidget {
  const LiveInputBar({super.key, required this.onSend});

  /// Bytes for the terminal.
  final ValueChanged<String> onSend;

  /// What the terminal receives for [text]: one line is typed and sent;
  /// several go as a bracketed paste first, so they stay one message.
  static List<String> encode(String text) =>
      text.contains('\n') ? ['\x1b[200~$text\x1b[201~', '\r'] : [text, '\r'];

  @override
  State<LiveInputBar> createState() => _LiveInputBarState();
}

class _LiveInputBarState extends State<LiveInputBar> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text;
    if (t.isEmpty) {
      widget.onSend('\r');
      return;
    }
    LiveInputBar.encode(t).forEach(widget.onSend);
    _text.clear();
  }

  Widget _key(String label, String bytes) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: OutlineButton(
      size: ButtonSize.small,
      onPressed: () => widget.onSend(bytes),
      child: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _key('Esc', '\x1b'),
              _key('Tab', '\t'),
              _key('⇧Tab', '\x1b[Z'),
              _key('↑', '\x1b[A'),
              _key('↓', '\x1b[B'),
              _key('⌃C', '\x03'),
            ],
          ),
        ),
        const Gap(6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 1,
                maxLines: 4,
                placeholder: const Text('Mensagem para o Claude'),
                onSubmitted: (_) => _send(),
              ),
            ),
            const Gap(6),
            PrimaryButton(
              density: ButtonDensity.icon,
              onPressed: _send,
              child: const Icon(LucideIcons.send, size: 16),
            ),
          ],
        ),
      ],
    ),
  );
}
