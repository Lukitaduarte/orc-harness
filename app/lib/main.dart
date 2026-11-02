import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'src/harness_store.dart';
import 'src/ui/workspace_screen.dart';

void main() {
  runApp(OrcHarnessApp(HarnessStore()));
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
