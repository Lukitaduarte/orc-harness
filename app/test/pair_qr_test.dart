import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/connect_dialog.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('the app shows a QR to pair the phone', (tester) async {
    final d = DaemonClient()..status = LinkStatus.connected;
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadcnApp(
        home: Builder(
          builder: (context) => PrimaryButton(
            onPressed: () => showConnectDialog(context, store),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Mostrar QR de pareamento'));
    await tester.pump();
    expect(sent.last, {'type': 'new_pairing_ticket'});
    d.handle('{"type":"pairing_ticket","ticket":"orc1abcd"}');
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Copiar'), findsOneWidget);
    store.dispose();
    d.dispose();
  });
}
