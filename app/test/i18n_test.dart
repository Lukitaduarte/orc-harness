import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/i18n.dart';
import 'package:orc_harness/src/live/daemon_client.dart';
import 'package:orc_harness/src/ui/workspace_screen.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Map<String, dynamic> arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> placeholders(String text) =>
    RegExp(r'\{(\w+)[,}]').allMatches(text).map((m) => m.group(1)!).toSet();

void main() {
  test('every language has every text, with the same placeholders', () {
    final en = arb('en');
    final keys = en.keys.where((k) => !k.startsWith('@')).toSet();
    expect(keys.length, greaterThan(400));
    for (final lang in languageNames.keys.where((l) => l != 'en')) {
      final other = arb(lang);
      final otherKeys = other.keys.where((k) => !k.startsWith('@')).toSet();
      expect(otherKeys, keys, reason: '$lang has the same keys as en');
      for (final k in keys) {
        expect((other[k] as String).trim(), isNotEmpty, reason: '$lang.$k');
        expect(
          placeholders(other[k] as String),
          placeholders(en[k] as String),
          reason: '$lang.$k',
        );
      }
    }
  });

  for (final lang in ['en', 'es']) {
    testWidgets('the main screen in $lang', (tester) async {
      appLocale.value = Locale(lang);
      addTearDown(() => appLocale.value = const Locale('pt'));
      final d = DaemonClient();
      final store = HarnessStore(daemon: d);
      d.sendHook = (_) {};
      d.handle('{"type":"hello","accounts":["w"]}');
      store.selectWorkspace('live');
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ShadcnApp(
          locale: Locale(lang),
          localizationsDelegates: localizationsDelegates,
          supportedLocales: [for (final c in languageNames.keys) Locale(c)],
          home: WorkspaceScreen(store),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text(lang == 'en' ? 'SESSIONS' : 'SESIONES'), findsOneWidget);
      expect(
        find.text('Ready to work!'),
        findsOneWidget,
        reason: 'the orc speaks English everywhere',
      );
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      d.dispose();
    });
  }
}
