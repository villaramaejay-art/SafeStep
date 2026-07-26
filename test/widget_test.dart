// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:safe_step/main.dart';

void main() {
  testWidgets('SafeStep app renders login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SafeStepApp());

    expect(find.text('SafeStep'), findsOneWidget);
    expect(find.text('Sign In / Register'), findsOneWidget);
  });
}
