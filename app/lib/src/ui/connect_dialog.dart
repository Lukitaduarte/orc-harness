import 'dart:io';

import 'package:mobile_scanner/mobile_scanner.dart';
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
          constraints: const BoxConstraints(maxWidth: 520),
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
    final d = widget.store.daemon;
    if (d != null && d.status == LinkStatus.connected) d.listDevices();
  }

  /// Paired apps; revoking one drops it now and it must pair again.
  List<Widget> _devices(DaemonClient d) => [
    const Gap(16),
    const Text('Aparelhos pareados').small().medium(),
    const Gap(6),
    for (final dev in d.devices)
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(
              dev['connected'] == true ? LucideIcons.wifi : LucideIcons.wifiOff,
              size: 14,
            ),
            const Gap(8),
            Expanded(
              child: Text(
                '${dev['name']}${dev['id'] == d.thisDevice ? ' (este)' : ''}',
              ).small(),
            ),
            if (dev['id'] != d.thisDevice)
              DestructiveButton(
                size: ButtonSize.small,
                onPressed: () => d.revokeDevice(dev['id'] as String),
                child: const Text('Revogar'),
              ),
          ],
        ),
      ),
  ];

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
          if (d.devices.isNotEmpty) ..._devices(d),
          const Gap(16),
          const Text(
            'No Mac onde o orcd roda: `orcd serve` e, em outro terminal, `orcd pair`. '
            'Cole aqui o ticket (vale 10 minutos, uma vez).',
          ).xSmall().muted(),
          if (Platform.isIOS || Platform.isAndroid) ...[
            const Gap(8),
            OutlineButton(
              leading: const Icon(LucideIcons.scanQrCode, size: 16),
              onPressed: () async {
                final code = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const _ScanTicket()),
                );
                if (code != null) _ticket.text = code;
              },
              child: const Text('Escanear o QR do `orcd pair`'),
            ),
          ],
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
                          final live = widget.store.liveWorkspaces;
                          if (live.isNotEmpty) {
                            widget.store.selectWorkspace(live.first.id);
                          }
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

/// Camera view that returns the first pairing ticket it reads.
class _ScanTicket extends StatefulWidget {
  const _ScanTicket();

  @override
  State<_ScanTicket> createState() => _ScanTicketState();
}

class _ScanTicketState extends State<_ScanTicket> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GhostButton(
                density: ButtonDensity.icon,
                onPressed: () => Navigator.of(context).pop(),
                child: const Icon(LucideIcons.x, size: 18),
              ),
              const Text('Aponte para o QR do orcd pair').small(),
            ],
          ),
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final code = capture.barcodes
                    .map((b) => b.rawValue)
                    .whereType<String>()
                    .where((v) => v.startsWith('orc1'))
                    .firstOrNull;
                if (code == null || _done) return;
                _done = true;
                Navigator.of(context).pop(code);
              },
            ),
          ),
        ],
      ),
    ),
  );
}
