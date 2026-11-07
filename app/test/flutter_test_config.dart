import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:orc_harness/src/i18n.dart';

/// Widget tests read the Portuguese texts (and check the others in
/// i18n_test.dart).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  appLocale.value = const Locale('pt');
  await testMain();
}
