import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/live/daemon_client.dart';

void main() {
  test('alerts on changes worth your attention, never on replays', () {
    final d = DaemonClient();
    final alerts = <(String, String)>[];
    d.onAlert = (t, b) => alerts.add((t, b));
    d.handle(
      '{"type":"sessions","sessions":[{"id":"s1","account_id":"w","cwd":"/r/app","state":"running","model":null,"claude_session_id":"u","branch":"feat/1-login"}]}',
    );
    d.handle(
      '{"type":"session_state","session_id":"s1","state":"waiting_input"}',
    );
    d.handle(
      '{"type":"session_state","session_id":"s1","state":"waiting_input"}',
    );
    expect(alerts, [
      ('Something need doing?', 'feat/1-login precisa de uma resposta.'),
    ]);

    d.handle(
      '{"type":"env_request","id":"e1","session_id":"s1","name":"API_TOKEN"}',
    );
    expect(alerts.last.$2, contains('API_TOKEN'));

    d.handle(
      jsonEncode({
        'type': 'plans',
        'plans': [
          {
            'id': 'p',
            'name': 'Push',
            'project_id': 'web',
            'markdown': '',
            'state': {},
          },
        ],
      }),
    );
    Map<String, Object?> card(int n, String state) => {
      'number': n,
      'state': state,
      'branch': 'b$n',
      'session_id': null,
      'pr': null,
      'pr_url': null,
      'note': state == 'failed' ? 'branch existe' : null,
    };
    void run(List<Map<String, Object?>> cards) => d.handle(
      jsonEncode({'type': 'plan_run', 'plan_id': 'p', 'cards': cards}),
    );
    final count = alerts.length;
    run([card(1, 'review'), card(2, 'todo')]);
    expect(alerts.length, count, reason: 'the first report is a replay');
    run([card(1, 'done'), card(2, 'failed')]);
    expect(alerts.sublist(count), [
      ("Job's done!", 'Push · card #1 foi feito.'),
      ('Card parou', 'Push · card #2: branch existe.'),
    ]);
    d.dispose();
  });

  test('a deploy waiting for your OK shows once and goes when decided', () {
    final d = DaemonClient();
    final alerts = <(String, String)>[];
    final sent = <Map<String, Object?>>[];
    d.onAlert = (t, b) => alerts.add((t, b));
    d.sendHook = sent.add;
    const msg =
        '{"type":"approval","id":"a1","session_id":"s1","action":"deploy no Railway: railway up"}';
    d.handle(msg);
    d.handle(msg);
    expect(d.approvals.length, 1);
    expect(alerts.single.$1, 'Precisa do seu OK');
    d.resolveApproval('a1', true);
    expect(sent.last, {
      'type': 'resolve_approval',
      'id': 'a1',
      'approve': true,
    });
    expect(d.approvals, isEmpty);
    d.handle(msg.replaceFirst('a1', 'a2'));
    d.handle('{"type":"approval_resolved","id":"a2","approved":false}');
    expect(d.approvals, isEmpty, reason: 'timed out in the daemon');
    d.dispose();
  });

  test('devices keep which one is this after a broadcast', () {
    final d = DaemonClient();
    d.handle(
      '{"type":"devices","devices":[{"id":"a","name":"Mac","paired_at":1,"connected":true,"this":true},{"id":"b","name":"iPhone","paired_at":1,"connected":true,"this":false}]}',
    );
    expect(d.thisDevice, 'a');
    d.handle(
      '{"type":"devices","devices":[{"id":"a","name":"Mac","paired_at":1,"connected":true,"this":false}]}',
    );
    expect((d.thisDevice, d.devices.length), ('a', 1));
    d.dispose();
  });

  test('whoever types gets their terminal size back', () {
    final d = DaemonClient();
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    d.resize('s1', 100, 30);
    // The phone resized it meanwhile: the grid comes at 40x20.
    d.handle(
      '{"type":"grid_diff","session_id":"s1","diff":{"cols":40,"rows":20,"lines":[],"cursor":{"row":0,"col":0,"visible":true}}}',
    );
    sent.clear();
    d.input('s1', 'a');
    expect(sent.map((m) => m['type']), ['resize', 'input']);
    expect((sent.first['cols'], sent.first['rows']), (100, 30));
    // Same size: just the keys.
    d.handle(
      '{"type":"grid_diff","session_id":"s1","diff":{"cols":100,"rows":30,"lines":[],"cursor":{"row":0,"col":0,"visible":true}}}',
    );
    sent.clear();
    d.input('s1', 'b');
    expect(sent.map((m) => m['type']), ['input']);
    d.dispose();
  });
}
