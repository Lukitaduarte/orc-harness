import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  runApp(const OrcHarnessApp());
}

class OrcHarnessApp extends StatelessWidget {
  const OrcHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadcnApp(
      title: 'orc-harness',
      theme: const ThemeData(colorScheme: ColorSchemes.lightZinc, radius: 0.5),
      darkTheme: const ThemeData(colorScheme: ColorSchemes.darkZinc, radius: 0.5),
      home: const Scaffold(
        child: Center(child: Text('orc-harness')),
      ),
    );
  }
}
