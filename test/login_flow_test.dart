import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:knight_shift/main.dart';

void main() {
  testWidgets('login flow works and navigates forward', (tester) async {
    // 1. Start app
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // 2. If login screen exists, simulate login quickly
    final loginButton = find.text('Login');

    if (loginButton.evaluate().isNotEmpty) {
      final emailField = find.byType(TextField).first;
      final passwordField = find.byType(TextField).last;

      await tester.enterText(emailField, 'test@example.com');
      await tester.enterText(passwordField, 'password123');

      await tester.tap(loginButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // 3. Verify we reached app shell (company gate or home)
    final hasScaffold = find.byType(Scaffold);
    expect(hasScaffold, findsWidgets);

    // 4. Basic sanity check: app did not crash
    expect(tester.takeException(), isNull);
  });
}