import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orc_harness/src/live/live_terminal.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets(
    'a focused terminal does not steal the keyboard from a field on rebuilds',
    (tester) async {
      final field = TextEditingController();
      final rebuild = ValueNotifier(0);
      final sent = <String>[];
      await tester.pumpWidget(
        ShadcnApp(
          home: Column(
            children: [
              SizedBox(width: 300, child: TextField(controller: field)),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: rebuild,
                  builder: (context, _, _) => LiveTerminal(
                    grid: null,
                    focused: true,
                    onInput: sent.add,
                    onResize: (_, _) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      // You click the field (a dialog's, the new account's name) and type,
      // while the app rebuilds every second.
      await tester.tap(find.byType(TextField));
      await tester.pump();
      bool fieldHasKeyboard() => tester
          .widget<EditableText>(find.byType(EditableText))
          .focusNode
          .hasFocus;
      expect(fieldHasKeyboard(), isTrue);
      for (var i = 0; i < 3; i++) {
        rebuild.value++;
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.pump();
        expect(
          fieldHasKeyboard(),
          isTrue,
          reason: 'rebuild $i took the keyboard',
        );
      }
      expect(sent, isEmpty, reason: 'nothing went to the terminal');
    },
  );
}
