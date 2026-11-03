import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Asks before something that cannot be undone; true when confirmed.
Future<bool> confirm(
  BuildContext context,
  String title,
  String body,
  String action,
) async {
  final ok = await showOverlay<bool>(
    context,
    DialogConfiguration<bool>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title).large().semiBold(),
                  const Gap(8),
                  Text(body).small().muted(),
                  const Gap(20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlineButton(
                        onPressed: () => closeOverlay(context, false),
                        child: const Text('Cancelar'),
                      ),
                      const Gap(8),
                      DestructiveButton(
                        onPressed: () => closeOverlay(context, true),
                        child: Text(action),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  ).future;
  return ok ?? false;
}
