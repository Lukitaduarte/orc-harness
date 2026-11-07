import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../harness_store.dart';
import '../i18n.dart';
import 'orc_sprite.dart';
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

  /// The app's language: the system's, or one you pick (remembered).
  List<Widget> _language(BuildContext context) => [
    const Gap(16),
    Text(context.l10n.language).small().medium(),
    const Gap(6),
    ValueListenableBuilder(
      valueListenable: appLocale,
      builder: (context, locale, _) => Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final (code, name) in [
            (null, context.l10n.languageSystem),
            for (final e in languageNames.entries) (e.key, e.value),
          ])
            (locale?.languageCode == code)
                ? SecondaryButton(
                    size: ButtonSize.small,
                    onPressed: () {},
                    child: Text(name),
                  )
                : GhostButton(
                    size: ButtonSize.small,
                    onPressed: () => setLanguage(code),
                    child: Text(name),
                  ),
        ],
      ),
    ),
  ];

  /// A QR for the next device: scan it with the phone's app (Escanear o
  /// QR) or paste the text. One use, 10 minutes.
  List<Widget> _pairAnother(DaemonClient d) {
    final t = d.pairingTicket;
    final fresh =
        t != null &&
        DateTime.now().difference(t.$2) < const Duration(minutes: 10);
    return [
      const Gap(16),
      Text(context.l10n.shellPairAnother).small().medium(),
      const Gap(6),
      if (!fresh)
        OutlineButton(
          leading: const Icon(LucideIcons.qrCode, size: 14),
          onPressed: d.requestPairingTicket,
          child: Text(context.l10n.shellShowPairingQr),
        )
      else ...[
        Center(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(10),
            child: QrImageView(
              data: t.$1,
              size: 240,
              errorCorrectionLevel: QrErrorCorrectLevel.L,
            ),
          ),
        ),
        const Gap(6),
        Row(
          children: [
            Expanded(child: Text(context.l10n.shellPairQrHint)),
            GhostButton(
              size: ButtonSize.small,
              leading: const Icon(LucideIcons.copy, size: 12),
              onPressed: () => Clipboard.setData(ClipboardData(text: t.$1)),
              child: Text(context.l10n.shellCopy),
            ),
          ],
        ),
      ],
    ];
  }

  /// Paired apps; revoking one drops it now and it must pair again.
  List<Widget> _devices(DaemonClient d) => [
    const Gap(16),
    Text(context.l10n.shellPairedDevices).small().medium(),
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
                dev['id'] == d.thisDevice
                    ? context.l10n.shellThisDevice('${dev['name']}')
                    : '${dev['name']}',
              ).small(),
            ),
            if (dev['id'] != d.thisDevice)
              DestructiveButton(
                size: ButtonSize.small,
                onPressed: () => d.revokeDevice(dev['id'] as String),
                child: Text(context.l10n.shellRevoke),
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
      return Text(context.l10n.shellNoDaemon).small().muted();
    }
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.shellConnectDaemon).large().semiBold(),
          if (d.status == LinkStatus.connecting) ...[
            const Gap(10),
            OrcSprite(scale: 3, says: context.l10n.orcWorkWork),
          ],
          const Gap(4),
          Text(switch (d.status) {
            LinkStatus.connected => context.l10n.shellConnectedCounts(
              d.accounts.length,
              d.sessions.length,
            ),
            LinkStatus.connecting => context.l10n.shellConnecting,
            LinkStatus.disconnected =>
              d.paired
                  ? context.l10n.shellPairedOffline
                  : context.l10n.shellNotPaired,
          }).small().muted(),
          if (d.error != null && d.status != LinkStatus.connected) ...[
            const Gap(6),
            Text(
              d.error!,
            ).xSmall().medium(color: Theme.of(context).colorScheme.destructive),
          ],
          ..._language(context),
          if (d.status == LinkStatus.connected) ..._pairAnother(d),
          if (d.devices.isNotEmpty) ..._devices(d),
          const Gap(16),
          Text(context.l10n.shellPairInstructions).xSmall().muted(),
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
              child: Text(context.l10n.shellScanPairQr),
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
                child: Text(context.l10n.shellClose),
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
                child: Text(context.l10n.shellPairAndConnect),
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
              Text(context.l10n.shellPointAtQr).small(),
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
