import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The daemon that ships inside the macOS app (`Contents/Resources/bin`, put
/// there by the release build): installed as a login service on first
/// launch, updated when the app brings a newer one, and paired with over
/// its owner-only local socket. Development builds carry none and pair by
/// ticket, as before.
class LocalDaemon {
  LocalDaemon({String? home, String? bundled})
    : home = home ?? '${Platform.environment['HOME']}/.orc',
      bundled = bundled ?? _bundledOrcd();

  /// `~/.orc`, the service's home.
  final String home;

  /// The app's own `orcd`, or null when the app carries none.
  final String? bundled;

  static String? _bundledOrcd() {
    if (!Platform.isMacOS) return null;
    // …/Orc Harness.app/Contents/MacOS/Orc Harness
    final contents = File(Platform.resolvedExecutable).parent.parent;
    final orcd = File('${contents.path}/Resources/bin/orcd');
    return orcd.existsSync() ? orcd.path : null;
  }

  String get installed => '$home/bin/orcd';

  /// Installs the service, or reinstalls it when the app's daemon differs
  /// from the installed one. With [onlyUpdate], a Mac without the service
  /// (one paired with a daemon elsewhere) is left alone.
  Future<void> ensureInstalled({bool onlyUpdate = false}) async {
    final from = bundled;
    if (from == null) return;
    final have = File(installed);
    if (!await have.exists()) {
      if (onlyUpdate) return;
    } else if (await _sameDaemon(from, have.path) && await _running()) {
      return;
    }
    final r = await Process.run(from, ['install']);
    if (r.exitCode != 0) {
      throw Exception('orcd install: ${'${r.stderr}'.trim()}');
    }
    // The service opens its socket a moment after launchd starts it.
    for (var i = 0; i < 100 && !await _running(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// This Mac runs the harness's service (its socket is there).
  Future<bool> serviceHere() async =>
      bundled != null && await File(installed).exists();

  /// The app carries a daemon different from the installed one, or the
  /// service is not running: the update screen comes first.
  Future<bool> needsUpdate() async {
    final from = bundled;
    if (from == null || !await File(installed).exists()) return false;
    return !await _running() || !await _sameDaemon(from, installed);
  }

  /// A one-time pairing ticket from the local service, installing it first
  /// if needed. Null when the app carries no daemon.
  Future<String?> ticket() async {
    if (bundled == null) return null;
    await ensureInstalled();
    final r = await Process.run(installed, ['pair']);
    final ticket = '${r.stdout}'.trim().split('\n').first.trim();
    if (r.exitCode != 0 || !ticket.startsWith('orc1')) {
      throw Exception('orcd pair: ${'${r.stderr}'.trim()}');
    }
    return ticket;
  }

  Future<bool> _running() async {
    try {
      final s = await Socket.connect(
        InternetAddress('$home/orcd.sock', type: InternetAddressType.unix),
        0,
      );
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Same release: by `orcd version` (the installed copy may be re-signed,
  /// so its bytes differ), or by bytes for daemons that predate it.
  static Future<bool> _sameDaemon(String bundled, String installed) async {
    Future<String?> version(String path) async {
      try {
        final r = await Process.run(path, ['version']);
        final v = '${r.stdout}'.trim();
        return r.exitCode == 0 && v.isNotEmpty ? v : null;
      } catch (_) {
        return null;
      }
    }

    final (a, b) = (await version(bundled), await version(installed));
    if (a != null && b != null) return a == b;
    return _same(File(bundled), File(installed));
  }

  static Future<bool> _same(File a, File b) async {
    if (await a.length() != await b.length()) return false;
    final (x, y) = (await a.readAsBytes(), await b.readAsBytes());
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}

/// Builds before 0.1.0 ran in the macOS sandbox, which kept the app's files
/// in its container; they move to the plain support folder once.
Future<void> leaveSandboxContainer() async {
  if (!Platform.isMacOS) return;
  final support = await getApplicationSupportDirectory();
  final id = support.path.split('/').last;
  final old = Directory(
    '${Platform.environment['HOME']}/Library/Containers/$id/Data/Library/Application Support/$id',
  );
  if (support.path == old.path || !await old.exists()) return;
  await support.create(recursive: true);
  for (final f in old.listSync().whereType<File>()) {
    final to = File('${support.path}/${f.uri.pathSegments.last}');
    if (!await to.exists()) await f.copy(to.path);
  }
}
