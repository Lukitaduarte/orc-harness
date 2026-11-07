import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../l10n/app_localizations.dart';

export '../l10n/app_localizations.dart';

/// Languages offered, by code, in their own names. Adding one: an ARB file
/// in lib/l10n (see l10n.yaml) and a line here.
const languageNames = {'en': 'English', 'pt': 'Português', 'es': 'Español'};

/// The language you picked; null follows the system.
final appLocale = ValueNotifier<Locale?>(null);

/// The language in effect for text built outside widgets (notifications,
/// prompts): your pick, else the system's if offered, else English.
Locale get effectiveLocale {
  final picked = appLocale.value;
  if (picked != null) return picked;
  final system = PlatformDispatcher.instance.locale.languageCode;
  return Locale(languageNames.containsKey(system) ? system : 'en');
}

/// Texts outside widgets.
AppLocalizations get l10n => lookupAppLocalizations(effectiveLocale);

extension L10nContext on BuildContext {
  /// The app's texts in the current language. Outside a localized app (some
  /// widget tests) it falls back to the effective language.
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      lookupAppLocalizations(effectiveLocale);
}

/// Delegates for ShadcnApp: ours, Flutter's, and shadcn's own texts (it
/// ships English only; other languages fall back to it).
const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  _ShadcnFallback(),
];

class _ShadcnFallback extends LocalizationsDelegate<ShadcnLocalizations> {
  const _ShadcnFallback();

  @override
  bool isSupported(Locale locale) =>
      languageNames.containsKey(locale.languageCode);

  @override
  Future<ShadcnLocalizations> load(Locale locale) =>
      SynchronousFuture(lookupShadcnLocalizations(const Locale('en')));

  @override
  bool shouldReload(_ShadcnFallback old) => false;
}

Future<File> _file() async =>
    File('${(await getApplicationSupportDirectory()).path}/language');

/// Loads your pick (kept between launches).
Future<void> loadLanguage() async {
  try {
    final code = (await (await _file()).readAsString()).trim();
    if (languageNames.containsKey(code)) appLocale.value = Locale(code);
  } catch (_) {}
}

/// Picks a language (null: the system's) and remembers it.
Future<void> setLanguage(String? code) async {
  appLocale.value = code == null ? null : Locale(code);
  try {
    final f = await _file();
    if (code == null) {
      if (await f.exists()) await f.delete();
    } else {
      await f.writeAsString(code);
    }
  } catch (_) {}
}
