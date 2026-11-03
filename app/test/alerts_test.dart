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
      ('Esperando você', 'feat/1-login precisa de uma resposta.'),
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
      ('Card mergeado', 'Push · card #1 foi feito.'),
      ('Card parou', 'Push · card #2: branch existe.'),
    ]);
    d.dispose();
  });
}
