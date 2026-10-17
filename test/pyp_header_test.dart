import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pyp_app/theme/app_theme.dart';
import 'package:pyp_app/widgets/pyp_header.dart';

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

  group('PYPAppHeader Widget Tests', () {
    testWidgets(
      'PYPAppHeader renders logo asset with BoxFit.contain and user details',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              appBar: PYPAppHeader(
                title: 'Incoming Requests',
                userRoles: const {'photographer'},
                userEmail: 'photographer@pyp.com',
                onSignOut: () {},
              ),
            ),
          ),
        );

        // Verify title is rendered
        expect(find.text('Incoming Requests'), findsOneWidget);

        // Verify logo image is present and uses BoxFit.contain
        final imageFinder = find.byType(Image);
        expect(imageFinder, findsOneWidget);
        final imageWidget = tester.widget<Image>(imageFinder);
        expect(imageWidget.fit, BoxFit.contain);

        // Verify username truncation and role badge
        expect(find.text('photographer'), findsOneWidget);
        expect(find.text('PHOTOGRAPHER'), findsOneWidget);

        // Verify logout icon
        expect(find.byIcon(Icons.logout), findsOneWidget);
      },
    );

    testWidgets(
      'PYPAppHeader handles multiple roles and long emails gracefully without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 800); // Narrow device width
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              appBar: PYPAppHeader(
                title: 'Marketplace',
                userRoles: const {'customer', 'photographer', 'admin'},
                userEmail: 'aravindhan.verylongemailaddress@pyp.com',
                onSignOut: () {},
              ),
            ),
          ),
        );

        expect(find.text('Marketplace'), findsOneWidget);
        expect(find.text('aravindhan.verylongemailaddress'), findsOneWidget);
        expect(find.text('CUSTOMER'), findsOneWidget);
        expect(find.text('PHOTOGRAPHER'), findsOneWidget);
        expect(find.text('ADMIN'), findsOneWidget);
      },
    );
  });
}
