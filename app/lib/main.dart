import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'src/harness_store.dart';
import 'src/live/daemon_client.dart';
import 'src/rust/frb_generated.dart';
import 'src/ui/workspace_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  final daemon = DaemonClient()..onAlert = await _systemAlerts();
  daemon.start();
  runApp(OrcHarnessApp(HarnessStore(daemon: daemon)));
}

/// System notifications, shown only while the app is not in front.
Future<void Function(String, String)?> _systemAlerts() async {
  final plugin = FlutterLocalNotificationsPlugin();
  const darwin = DarwinInitializationSettings();
  try {
    await plugin.initialize(
      settings: const InitializationSettings(macOS: darwin, iOS: darwin),
    );
  } catch (_) {
    return null; // a platform without notifications
  }
  var next = 0;
  return (title, body) {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      return;
    }
    plugin.show(
      id: next++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        macOS: DarwinNotificationDetails(),
        iOS: DarwinNotificationDetails(),
      ),
    );
  };
}

class OrcHarnessApp extends StatelessWidget {
  const OrcHarnessApp(this.store, {super.key});

  final HarnessStore store;

  @override
  Widget build(BuildContext context) {
    return ShadcnApp(
      title: 'orc-harness',
      debugShowCheckedModeBanner: false,
      theme: const ThemeData(colorScheme: ColorSchemes.lightZinc, radius: 0.5),
      darkTheme: const ThemeData(
        colorScheme: ColorSchemes.darkZinc,
        radius: 0.5,
      ),
      home: WorkspaceScreen(store),
    );
  }
}
