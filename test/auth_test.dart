import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pyp_app/main.dart';
import 'package:pyp_app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getAll') {
              return <String, dynamic>{};
            }
            return null;
          },
        );

    try {
      await Supabase.initialize(
        url: 'http://127.0.0.1:54321',
        publishableKey: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
      );
    } catch (_) {
      // Supabase already initialized
    }
  });

  group('Authentication & Password Reset Tests', () {
    testWidgets('AuthScreen shows Forgot Password link in Sign In mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme, home: const AuthScreen()),
      );

      expect(find.text('Forgot Password?'), findsOneWidget);
    });

    testWidgets('Forgot Password displays error snackbar when email is empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme, home: const AuthScreen()),
      );

      await tester.tap(find.text('Forgot Password?'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please enter your email address to reset your password.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Forgot Password displays error snackbar when email format is invalid',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.darkTheme, home: const AuthScreen()),
        );

        final emailField = find.widgetWithText(TextField, 'Email Address');
        await tester.enterText(emailField, 'notanemail');

        await tester.tap(find.text('Forgot Password?'));
        await tester.pumpAndSettle();

        expect(
          find.text('Please enter a valid email address.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Resend Confirmation displays error snackbar when email is empty',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.darkTheme, home: const AuthScreen()),
        );

        await tester.tap(find.text('Resend Confirmation?'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Please enter your email address to resend confirmation email.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Resend Confirmation displays error snackbar when email format is invalid',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.darkTheme, home: const AuthScreen()),
        );

        final emailField = find.widgetWithText(TextField, 'Email Address');
        await tester.enterText(emailField, 'notanemail');

        await tester.tap(find.text('Resend Confirmation?'));
        await tester.pumpAndSettle();

        expect(
          find.text('Please enter a valid email address.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('ResetPasswordScreen renders new password fields and action', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: ResetPasswordScreen(onPasswordResetComplete: () {}),
        ),
      );

      expect(find.text('Set New Password'), findsOneWidget);
      expect(find.text('New Password'), findsOneWidget);
      expect(find.text('Confirm New Password'), findsOneWidget);
      expect(find.text('Update Password'), findsOneWidget);
    });
  });
}
