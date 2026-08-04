import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:knight_shift/main.dart';

void main() {
  testWidgets('login flow works and navigates forward', (tester) async {
    // 1. Start app
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // 2. Find login inputs
    final emailField = find.byType(TextField).first;
    final passwordField = find.byType(TextField).last;
    final loginButton = find.text('Login');

    // 3. Enter credentials
    await tester.enterText(emailField, 'test@example.com');
    await tester.enterText(passwordField, 'password123');

    await tester.pumpAndSettle();

    // 4. Tap login
    await tester.tap(loginButton);
    await tester.pump();

    // 5. Wait for navigation / state update
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 6. Verify we left login screen
    expect(find.text('Login'), findsNothing);

    // 7. Verify we reached app shell (company gate or home)
    final hasScaffold = find.byType(Scaffold);
    expect(hasScaffold, findsWidgets);
  });
}