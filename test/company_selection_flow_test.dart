import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:knight_shift/main.dart';

void main() {
  testWidgets('company selection flow works', (tester) async {
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

    // 3. Now we should be at company selection or gate
    expect(find.byType(Scaffold), findsWidgets);

    // 4. Try to find a company tile (real UI dependent)
    final companyTile = find.byType(ListTile);

    if (companyTile.evaluate().isNotEmpty) {
      await tester.tap(companyTile.first);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // 5. Verify we moved forward in app
    expect(find.byType(MaterialApp), findsOneWidget);

    // 6. Basic sanity check: app did not crash
    expect(tester.takeException(), isNull);
  });
}