import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/emulator_pane.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

// A 1x2 PNG (portrait), enough for a frame.
final _png = base64Encode(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAACCAYAAACZgbYnAAAAEUlEQVR4nGNkYGD4z8DAwMAAAA4AAWl5SCYAAAAASUVORK5CYII=',
  ),
);

void main() {
  testWidgets('pick a device, turn it on, see it, tap it', (tester) async {
    final d = DaemonClient()..status = LinkStatus.connected;
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    var picked = '';
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> show(String id) => tester.pumpWidget(
      ShadcnApp(
        home: EmulatorPane(
          daemon: d,
          id: id,
          focused: true,
          onPick: (id) => picked = id,
        ),
      ),
    );

    await show('');
    expect(sent.last, {'type': 'list_emulators'});
    d.handle(
      '{"type":"emulators","emulators":['
      '{"id":"ios:U1","platform":"ios","name":"iPhone 17 Pro (26.5)","state":"off"},'
      '{"id":"android:pixel","platform":"android","name":"pixel","state":"off"}]}',
    );
    await tester.pump();
    await tester.tap(find.text('iPhone 17 Pro (26.5)'));
    expect(picked, 'ios:U1');

    await show('ios:U1');
    await tester.tap(find.text('Ligar'));
    expect(sent.last, {
      'type': 'emulator',
      'id': 'ios:U1',
      'action': {'type': 'boot'},
    });
    // On: the pane asks for its screen, and gets frames.
    d.handle(
      '{"type":"emulators","emulators":[{"id":"ios:U1","platform":"ios","name":"iPhone 17 Pro (26.5)","state":"on"}]}',
    );
    await tester.pump();
    expect(sent.last, {
      'type': 'emulator',
      'id': 'ios:U1',
      'action': {'type': 'watch'},
    });
    d.handle(
      '{"type":"emulator_frame","id":"ios:U1","image":"$_png","width":1,"height":2}',
    );
    await tester.pump();
    final screen = tester.getRect(find.byType(Image));
    await tester.tapAt(
      screen.topLeft + Offset(screen.width / 4, screen.height / 2),
    );
    await tester.pump();
    final tap = sent.last['action'] as Map;
    expect(tap['type'], 'tap');
    expect(tap['x'] as double, closeTo(0.25, 0.02));
    expect(tap['y'] as double, closeTo(0.5, 0.02));

    // An agent driving it lights the tool up.
    d.handle('{"type":"emulator_use","id":"ios:U1","session_id":"s2"}');
    expect(d.emulatorUsedBy, 's2');

    // Leaving the pane stops the stream.
    await tester.pumpWidget(const SizedBox());
    expect(sent.last, {
      'type': 'emulator',
      'id': 'ios:U1',
      'action': {'type': 'unwatch'},
    });
    d.dispose();
  });
}
