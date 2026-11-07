// Renders the README screenshots from the real screens with the demo data:
//   cd app && flutter test test_screenshots
// Writes PNGs to docs/screenshots/.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/harness_store.dart';
import 'package:orc_harness/src/i18n.dart';
import 'package:orc_harness/src/ui/workspace_screen.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(rootBundle.load('packages/shadcn_flutter/$f'));
  }
  await loader.load();
}

Future<void> _fonts() async {
  await _font('packages/shadcn_flutter/GeistSans', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'lib/fonts/Geist-$w.otf',
  ]);
  await _font('packages/shadcn_flutter/GeistMono', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'lib/fonts/GeistMono-$w.otf',
  ]);
  await _font('packages/shadcn_flutter/LucideIcons', ['lib/icons/LucideIcons.ttf']);
  // Glyphs Geist lacks (⌘ ✻ ⏺ ⎿): the system's symbols font joins each
  // family as a fallback.
  final symbols = File('/System/Library/Fonts/Apple Symbols.ttf');
  if (symbols.existsSync()) {
    final bytes = ByteData.sublistView(symbols.readAsBytesSync());
    for (final family in ['Roboto', 'packages/shadcn_flutter/GeistSans', 'packages/shadcn_flutter/GeistMono']) {
      await (FontLoader(family)..addFont(Future.value(bytes))).load();
    }
  }
}

Future<void> _shot(WidgetTester tester, String name, Size size, void Function(HarnessStore) setup) async {
  final store = HarnessStore();
  setup(store);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: ShadcnApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        localizationsDelegates: localizationsDelegates,
        supportedLocales: [for (final c in languageNames.keys) Locale(c)],
        theme: const ThemeData(colorScheme: ColorSchemes.darkZinc, radius: 0.5),
        home: WorkspaceScreen(store),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('../docs/screenshots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  await tester.pumpWidget(const SizedBox());
  store.dispose();
  tester.view.reset();
}

void main() {
  setUpAll(() async {
    appLocale.value = const Locale('en');
    await _fonts();
  });

  const desktop = Size(1440, 900);
  testWidgets('sessions', (t) => _shot(t, 'sessions', desktop, (s) {}));
  testWidgets('plan', (t) => _shot(t, 'plan', desktop, (s) {
        s.openProjectView(s.workspaceProjects.firstWhere((p) => p.isPlanning).id);
      }));
  testWidgets('kanban', (t) => _shot(t, 'kanban', desktop, (s) {
        s.openProjectView(s.workspaceProjects.firstWhere((p) => !p.isPlanning).id);
      }));
  testWidgets('analytics', (t) => _shot(t, 'analytics', desktop, (s) => s.openAnalytics()));
  testWidgets('catalog', (t) => _shot(t, 'catalog', desktop, (s) => s.openCatalog()));
  testWidgets('phone', (t) => _shot(t, 'phone', const Size(390, 844), (s) {}));
}
