// PYP Application Smoke Test

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pyp_app/main.dart';

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

  testWidgets('PYPApp initializes correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const PYPApp());
    await tester.pumpAndSettle();
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('PICK YOUR PHOTOGRAPHER'), findsOneWidget);
  });
}
