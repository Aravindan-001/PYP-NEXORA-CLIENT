import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pyp_app/main.dart' as app;
import 'package:pyp_app/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PYP authentication controls and marketplace screen smoke test', (
    tester,
  ) async {
    final originalFlutterErrorOnError = FlutterError.onError;
    addTearDown(() {
      FlutterError.onError = originalFlutterErrorOnError;
    });

    // Launch the real app on the Android emulator.
    await app.main();

    // Restore Flutter's test error handler after app startup.
    FlutterError.onError = originalFlutterErrorOnError;

    await tester.pumpAndSettle();

    // Verify the initial client sign-in screen.
    expect(find.text('PYP'), findsOneWidget);
    expect(find.text('Client Sign In'), findsOneWidget);

    // Switch to the photographer portal.
    await tester.tap(find.text('Photographer Portal'));
    await tester.pumpAndSettle();

    expect(find.text('Photographer Sign In'), findsOneWidget);
    expect(find.text('Sign In as Photographer'), findsOneWidget);

    // Switch back to the client portal.
    await tester.tap(find.text('Client Portal'));
    await tester.pumpAndSettle();

    expect(find.text('Client Sign In'), findsOneWidget);

    // Verify the registration form can be opened and closed.
    await tester.ensureVisible(
      find.text("Don't have an account? Create Account"),
    );
    await tester.tap(find.text("Don't have an account? Create Account"));
    await tester.pumpAndSettle();

    expect(find.text('Create Client Account'), findsNWidgets(2));

    await tester.ensureVisible(find.text('Already have an account? Sign In'));
    await tester.tap(find.text('Already have an account? Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Client Sign In'), findsOneWidget);

    // Submit an empty form; this should stop at local validation.
    await tester.ensureVisible(find.text('Sign In as Client'));
    await tester.tap(find.text('Sign In as Client'));
    await tester.pumpAndSettle();

    expect(find.text('Email and password are required.'), findsOneWidget);

    // Let the previous validation snackbar disappear.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Use the first TextField, which is the client email field.
    final emailField = find.byType(TextField).first;

    await tester.ensureVisible(emailField);
    await tester.tap(emailField);
    await tester.enterText(emailField, 'not-an-email');

    // Keep the forgot-password action visible above the keyboard.
    final forgotPassword = find.text('Forgot Password?');
    await tester.ensureVisible(forgotPassword);
    await tester.tap(forgotPassword);
    await tester.pumpAndSettle();

    expect(find.text('Please enter a valid email address.'), findsOneWidget);

    // Render the actual DiscoverScreen on the emulator without
    // requiring an authenticated account or creating a booking.
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const app.DiscoverScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('EDITORIAL MARKETPLACE'), findsOneWidget);
    expect(find.text('Find Extraordinary Photographers'), findsOneWidget);
    expect(find.text('Any Budget'), findsOneWidget);
    expect(find.text('All Styles'), findsOneWidget);
    expect(find.text('Wedding'), findsOneWidget);
    expect(find.text('Portrait'), findsOneWidget);
  });
}
