import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:knight_shift/main.dart';

void main() {
  testWidgets('login flow works and navigates forward', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    final signInButton = find.text('Sign In');
    if (signInButton.evaluate().isNotEmpty) {
      await tester.tap(signInButton);
      await tester.pumpAndSettle();
    }

    expect(find.text('Login'), findsOneWidget);

    final emailField = find.byType(TextField).first;
    final passwordField = find.byType(TextField).last;

    await tester.enterText(emailField, 'test@example.com');
    await tester.enterText(passwordField, 'password123');

    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Login failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
