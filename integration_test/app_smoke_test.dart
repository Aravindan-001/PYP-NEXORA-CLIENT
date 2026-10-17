import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pyp_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PYP launches and displays the client sign-in screen',
      (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    expect(find.text('PYP'), findsOneWidget);
    expect(find.text('PICK YOUR PHOTOGRAPHER'), findsOneWidget);
    expect(find.text('Client Sign In'), findsOneWidget);
    expect(find.text('PORTAL TYPE'), findsOneWidget);
  });
}