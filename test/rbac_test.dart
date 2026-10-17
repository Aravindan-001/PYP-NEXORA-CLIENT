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

  group('RBAC UI & Role Assignment Widget Tests', () {
    testWidgets('AuthScreen shows role selection chips during signup', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme, home: const AuthScreen()),
      );

      // Initially shows sign-in mode for Client Portal
      expect(find.text('Client Sign In'), findsOneWidget);
      expect(find.text('PORTAL TYPE'), findsOneWidget);
      expect(find.text('Client Portal'), findsOneWidget);
      expect(find.text('Photographer Portal'), findsOneWidget);
      expect(
        find.text("Don't have an account? Create Account"),
        findsOneWidget,
      );

      // Tap toggle to switch to Sign Up mode
      await tester.tap(find.text("Don't have an account? Create Account"));
      await tester.pumpAndSettle();

      // Verify sign up fields and portal choice chips appear
      expect(find.text('Create Client Account'), findsAtLeast(1));
      expect(find.text('PORTAL TYPE'), findsOneWidget);
      expect(find.text('Client Portal'), findsOneWidget);
      expect(find.text('Photographer Portal'), findsOneWidget);

      // CRITICAL: Verify 'Admin' option is NOT available on public signup
      expect(find.text('Admin'), findsNothing);
      expect(find.text('Administrator'), findsNothing);

      // Select Photographer Portal chip
      await tester.tap(find.text('Photographer Portal'));
      await tester.pumpAndSettle();

      expect(find.text('Apply as Photographer'), findsOneWidget);
      expect(
        find.text(
          'Register as a photographer and submit your portfolio for review.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('AdminDashboardScreen renders stats overview bar and tabs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const AdminDashboardScreen(),
        ),
      );

      expect(find.text('Admin Platform Governance'), findsOneWidget);
      expect(find.text('Photographers'), findsOneWidget);
      expect(find.text('All Bookings'), findsOneWidget);
      expect(find.text('Clients'), findsOneWidget);
    });

    testWidgets(
      'DiscoverScreen renders editorial marketplace header and filter chips',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.darkTheme, home: const DiscoverScreen()),
        );

        expect(find.text('EDITORIAL MARKETPLACE'), findsOneWidget);
        expect(find.text('Find Extraordinary Photographers'), findsOneWidget);
        expect(find.text('Wedding'), findsOneWidget);
        expect(find.text('Portrait'), findsOneWidget);
      },
    );
  });
}
