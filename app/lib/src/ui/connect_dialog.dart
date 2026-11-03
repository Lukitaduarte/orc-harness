import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../live/daemon_client.dart';

/// Connects the app to orcd: paste the ticket from `orcd pair`.
Future<void> showConnectDialog(BuildContext context, HarnessStore store) {
  return showOverlay<void>(
    context,
    DialogConfiguration<void>(
      builder: (context) {
        final theme = Theme.of(context);
        return ConstrainedBox(
          constraints: const BoxConstraints.tightFor(width: 520),
          child: ModalBackdrop(
            borderRadius: theme.borderRadiusXl,
            child: OutlinedContainer(
              backgroundColor: theme.colorScheme.popover,
              padding: const EdgeInsets.all(20),
              child: _Connect(store),
            ),
          ),
        );
      },
    ),
  ).future;
}

class _Connect extends StatefulWidget {
  const _Connect(this.store);

  final HarnessStore store;

  @override
  State<_Connect> createState() => _ConnectState();
}

class _ConnectState extends State<_Connect> {
  final _ticket = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ticket.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ticket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.store.daemon;
    if (d == null) {
      return const Text('Este app foi iniciado sem o daemon.').small().muted();
    }
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Conectar daemon').large().semiBold(),
          const Gap(4),
          Text(switch (d.status) {
            LinkStatus.connected =>
              'Conectado: ${d.accounts.length} conta(s), ${d.sessions.length} sessão(ões).',
            LinkStatus.connecting => 'Conectando…',
            LinkStatus.disconnected =>
              d.paired ? 'Pareado, sem conexão agora.' : 'Ainda não pareado.',
          }).small().muted(),
          if (d.error != null && d.status != LinkStatus.connected) ...[
            const Gap(6),
            Text(
              d.error!,
            ).xSmall().medium(color: Theme.of(context).colorScheme.destructive),
          ],
          const Gap(16),
          const Text(
            'No Mac onde o orcd roda: `orcd serve` e, em outro terminal, `orcd pair`. '
            'Cole aqui o ticket (vale 10 minutos, uma vez).',
          ).xSmall().muted(),
          const Gap(8),
          TextField(
            controller: _ticket,
            minLines: 2,
            maxLines: 4,
            placeholder: const Text('orc1…'),
            style: Theme.of(context).typography.mono.copyWith(fontSize: 11),
          ),
          const Gap(16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlineButton(
                onPressed: () => closeOverlay(context),
                child: const Text('Fechar'),
              ),
              const Gap(8),
              PrimaryButton(
                onPressed:
                    _ticket.text.trim().startsWith('orc1') &&
                        d.status != LinkStatus.connecting
                    ? () async {
                        await d.pair(_ticket.text);
                        if (d.status == LinkStatus.connected &&
                            context.mounted) {
                          widget.store.selectWorkspace(
                            HarnessStore.liveWorkspace.id,
                          );
                          closeOverlay(context);
                        }
                      }
                    : null,
                child: const Text('Parear e conectar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
