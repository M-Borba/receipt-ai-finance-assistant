import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_ai_finance_assistant/shared/widgets/app_button.dart';

void main() {
  testWidgets('AppButton dispara onPressed y se bloquea con isLoading',
      (tester) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppButton(label: 'Procesar', onPressed: () => taps++),
        ),
      ),
    );

    expect(find.text('Procesar'), findsOneWidget);
    await tester.tap(find.text('Procesar'));
    expect(taps, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppButton(
            label: 'Procesar',
            isLoading: true,
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(ElevatedButton));
    expect(taps, 1, reason: 'no debe reaccionar mientras carga');
  });
}
