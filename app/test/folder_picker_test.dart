import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/repos.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets('picks a folder of the Mac through the daemon', (tester) async {
    final d = DaemonClient();
    final store = HarnessStore(daemon: d);
    final sent = <Map<String, Object?>>[];
    d.sendHook = sent.add;
    String? picked = 'unset';
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShadcnApp(
        home: Builder(
          builder: (context) => PrimaryButton(
            onPressed: () async =>
                picked = await showFolderPicker(context, store),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pump();
    expect(sent.last, {
      'type': 'browse_folders',
      'path': null,
      'hidden': false,
    });
    void folders(String path, List<Map<String, Object?>> f) => d.handle(
      jsonEncode({
        'type': 'folders',
        'path': path,
        'parent': '/Users',
        'folders': f,
      }),
    );
    folders('/Users/x', [
      {'name': 'Project', 'repo': false},
      {'name': 'blog', 'repo': true},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('git'), findsOneWidget, reason: 'repositories are marked');
    await tester.tap(find.text('Project'));
    await tester.pump();
    expect(sent.last['path'], '/Users/x/Project');
    folders('/Users/x/Project', [
      {'name': 'orc-harness', 'repo': true},
    ]);
    await tester.pumpAndSettle();
    await tester.tap(find.text('orc-harness'));
    await tester.pump();
    folders('/Users/x/Project/orc-harness', []);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar esta pasta'));
    await tester.pumpAndSettle();
    expect(picked, '/Users/x/Project/orc-harness');
    store.dispose();
    d.dispose();
  });
}
