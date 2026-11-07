import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'src/harness_store.dart';
import 'src/i18n.dart';
import 'src/live/daemon_client.dart';
import 'src/live/local_daemon.dart';
import 'src/rust/frb_generated.dart';
import 'src/ui/onboarding.dart';
import 'src/ui/workspace_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  await leaveSandboxContainer();
  await loadLanguage();
  final notifications = FlutterLocalNotificationsPlugin();
  final daemon = DaemonClient()..onAlert = await _systemAlerts(notifications);
  // A first launch asks for each permission in turn, in the onboarding.
  final onboarding = await needsOnboarding(daemon);
  daemon.start(autoPair: !onboarding);
  runApp(
    OrcHarnessApp(
      HarnessStore(daemon: daemon),
      onboarding: onboarding,
      requestNotifications: () async {
        await notifications
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        await notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      },
    ),
  );
}

/// System notifications, shown only while the app is not in front.
Future<void Function(String, String)?> _systemAlerts(
  FlutterLocalNotificationsPlugin plugin,
) async {
  // Asked for later, with a reason (onboarding), not at launch.
  const darwin = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
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

class OrcHarnessApp extends StatefulWidget {
  const OrcHarnessApp(
    this.store, {
    super.key,
    this.onboarding = false,
    this.requestNotifications,
  });

  final HarnessStore store;
  final bool onboarding;
  final Future<void> Function()? requestNotifications;

  @override
  State<OrcHarnessApp> createState() => _OrcHarnessAppState();
}

class _OrcHarnessAppState extends State<OrcHarnessApp> {
  late bool _onboarding = widget.onboarding;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: appLocale,
    builder: (context, locale, _) => ShadcnApp(
      title: 'Orc Harness',
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: localizationsDelegates,
      supportedLocales: [for (final code in languageNames.keys) Locale(code)],
      theme: const ThemeData(colorScheme: ColorSchemes.lightZinc, radius: 0.5),
      darkTheme: const ThemeData(
        colorScheme: ColorSchemes.darkZinc,
        radius: 0.5,
      ),
      home: _onboarding
          ? Onboarding(
              daemon: widget.store.daemon!,
              requestNotifications: widget.requestNotifications ?? () async {},
              onDone: () => setState(() => _onboarding = false),
            )
          : WorkspaceScreen(widget.store),
    ),
  );
}
