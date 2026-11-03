import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/browser_pane.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// 1×1 PNG.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

void main() {
  test('the workspace browser: state, frames, pane and agent profile', () {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.handle('{"type":"hello","accounts":["work"]}');
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"work","cwd":"/p","state":"idle","model":null,"claude_session_id":"u"}]}',
    );
    store.selectWorkspace('live');

    store.openBrowser(store.focusedLeafId);
    expect(sent.last, {
      'type': 'browser',
      'profile': 'live',
      'action': {'action': 'open', 'url': null},
    });
    expect(store.focusedSession, isNull, reason: 'a browser is not a session');
    // A session list update keeps the browser pane.
    d.handle('{"type":"sessions","sessions":[]}');
    expect(store.hiddenSessions, isEmpty);

    d.handle(
      '{"type":"browser_state","profile":"live","open":true,"url":"https://x.dev/"}',
    );
    d.handle(
      jsonEncode({
        'type': 'browser_frame',
        'profile': 'live',
        'jpeg': _png,
        'width': 800,
        'height': 600,
      }),
    );
    final b = d.browserOf('live');
    expect(
      (b.open, b.url, b.width, b.frame!.length),
      (true, 'https://x.dev/', 800, base64Decode(_png).length),
    );

    // The agent gets the workspace browser when it is picked in the profile.
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"work","cwd":"/p","state":"idle","model":null,"claude_session_id":"u"}]}',
    );
    final s = store.session('s1');
    expect(
      store.profileItems.any((i) => i.id == HarnessStore.workspaceBrowserItem),
      isTrue,
    );
    store.toggleItem(s, HarnessStore.workspaceBrowserItem);
    store.applyDraft(s);
    expect((sent.last['profile'] as Map)['browser'], 'live');
    store.dispose();
    d.dispose();
  });

  testWidgets('clicks and keys reach the page in its own coordinates', (
    tester,
  ) async {
    final d = DaemonClient();
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.handle(
      '{"type":"browser_state","profile":"live","open":true,"url":"about:blank"}',
    );
    d.handle(
      jsonEncode({
        'type': 'browser_frame',
        'profile': 'live',
        'jpeg': _png,
        'width': 1000,
        'height': 1000,
      }),
    );
    await tester.binding.setSurfaceSize(const Size(600, 600));
    await tester.pumpWidget(
      ShadcnApp(
        home: SizedBox(
          width: 600,
          height: 600,
          child: BrowserPane(daemon: d, profile: 'live', focused: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final resize = sent.lastWhere(
      (m) => (m['action'] as Map)['action'] == 'resize',
    );
    final page = tester.getRect(find.byType(Image));
    expect((resize['action'] as Map)['width'], page.width.round());

    await tester.tapAt(page.center);
    await tester.pump();
    final press = sent.firstWhere(
      (m) => ((m['action'] as Map)['event'] as Map?)?['type'] == 'mousePressed',
    );
    final ev = (press['action'] as Map)['event'] as Map;
    expect(
      (ev['x'] as double).round(),
      500,
      reason: 'pane center is page center',
    );
    expect((ev['y'] as double).round(), 500);
    expect(ev['button'], 'left');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    final events = sent
        .map((m) => (m['action'] as Map)['event'])
        .whereType<Map>()
        .where((e) => e['kind'] != 'mouse')
        .toList();
    expect(events, [
      {'kind': 'key', 'key': 'Enter', 'modifiers': 0},
      {'kind': 'text', 'text': 'a'},
    ]);
    d.dispose();
  });
}
