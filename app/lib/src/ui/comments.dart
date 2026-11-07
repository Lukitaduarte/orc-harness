import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../i18n.dart';
import '../model.dart';
import 'format.dart';

/// Messages of a thread or a card's notes, oldest first.
class CommentList extends StatelessWidget {
  const CommentList(this.comments, {required this.now, super.key});

  final List<Comment> comments;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in comments)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Avatar(
                  initials: c.byAgent ? 'C' : l10n.plansYouInitial,
                  size: 22,
                  backgroundColor: c.byAgent ? Colors.orange : scheme.muted,
                ),
                const Gap(8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(c.author).xSmall().semiBold(),
                          const Gap(6),
                          Text(
                            l10n.plansAgo(formatDuration(now.difference(c.at))),
                          ).xSmall().muted(),
                        ],
                      ),
                      const Gap(2),
                      Text(c.body).small(),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Text field plus send button; clears itself after sending.
class CommentComposer extends StatefulWidget {
  const CommentComposer({
    required this.onSend,
    this.placeholder,
    this.autofocus = false,
    super.key,
  });

  final ValueChanged<String> onSend;

  /// Defaults to "Escreva um comentário…" in the current language.
  final String? placeholder;
  final bool autofocus;

  @override
  State<CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<CommentComposer> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          placeholder: Text(
            widget.placeholder ?? context.l10n.plansWriteComment,
          ),
          minLines: 1,
          maxLines: 4,
          onSubmitted: (_) => _send(),
        ),
      ),
      const Gap(8),
      PrimaryButton(
        density: ButtonDensity.icon,
        onPressed: _controller.text.trim().isEmpty ? null : _send,
        child: const Icon(LucideIcons.send, size: 14),
      ),
    ],
  );
}
