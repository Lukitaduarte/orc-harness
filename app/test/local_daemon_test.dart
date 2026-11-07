import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/live/local_daemon.dart';

void main() {
  late Directory tmp;
  late String home;
  late String bundled;
  ServerSocket? service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('orc-local');
    home = '${tmp.path}/orc';
    await Directory(home).create();
    // A stand-in orcd: `install` copies itself into ~/.orc/bin and logs,
    // `pair` prints a ticket (and its QR on stderr, like the real one).
    bundled = '${tmp.path}/app/orcd';
    await File(bundled).create(recursive: true);
    await File(bundled).writeAsString('''#!/bin/sh
case "\$1" in
  install) mkdir -p "$home/bin"; cp "\$0" "$home/bin/orcd"; echo install >> "$home/log";;
  pair) echo orc1ticket; echo "QR" >&2;;
esac
''');
    await Process.run('chmod', ['+x', bundled]);
    // The service's socket, as launchd would start it.
    service = await ServerSocket.bind(
      InternetAddress('$home/orcd.sock', type: InternetAddressType.unix),
      0,
    );
  });

  tearDown(() async {
    await service?.close();
    await tmp.delete(recursive: true);
  });

  Future<int> installs() async {
    final log = File('$home/log');
    return await log.exists() ? (await log.readAsLines()).length : 0;
  }

  test('a fresh Mac gets the service installed and a ticket', () async {
    final d = LocalDaemon(home: home, bundled: bundled);
    expect(await d.ticket(), 'orc1ticket');
    expect(await installs(), 1);
    // Same daemon, running: nothing to do.
    await d.ensureInstalled(onlyUpdate: true);
    expect(await installs(), 1);
  });

  test('a new app version updates the installed daemon', () async {
    final d = LocalDaemon(home: home, bundled: bundled);
    await d.ensureInstalled();
    await File(bundled).writeAsString('\n# v2', mode: FileMode.append);
    await d.ensureInstalled(onlyUpdate: true);
    expect(await installs(), 2);
  });

  test('a Mac paired elsewhere is left alone', () async {
    await LocalDaemon(home: home, bundled: bundled)
        .ensureInstalled(onlyUpdate: true);
    expect(await installs(), 0);
    expect(File('$home/bin/orcd').existsSync(), isFalse);
  });

  test('a build without a daemon pairs by ticket, as before', () async {
    expect(await LocalDaemon(home: home, bundled: null).ticket(), isNull);
  });
}
