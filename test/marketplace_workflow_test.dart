import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pyp_app/main.dart';
import 'package:pyp_app/theme/app_theme.dart';
import 'package:pyp_app/widgets/booking_card.dart';
import 'package:pyp_app/widgets/booking_chat_screen.dart';
import 'package:pyp_app/widgets/booking_dialog.dart';
import 'package:pyp_app/widgets/photographer_card.dart';

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

  group('Marketplace Workflow & Role Experience Tests', () {
    testWidgets(
      'Client Profile Screen renders client view and option to apply as photographer',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: ClientProfileScreen(onRoleChanged: () {}),
          ),
        );

        expect(find.text('CLIENT ACCOUNT'), findsOneWidget);
        expect(
          find.text('Are you a Professional Photographer?'),
          findsOneWidget,
        );
        expect(find.text('Apply as Photographer'), findsOneWidget);
        expect(find.text('Sign Out'), findsOneWidget);
      },
    );

    testWidgets(
      'DiscoverScreen renders search input, budget dropdown, specialization dropdown, and category chips',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.darkTheme, home: const DiscoverScreen()),
        );

        expect(find.text('EDITORIAL MARKETPLACE'), findsOneWidget);
        expect(find.text('Find Extraordinary Photographers'), findsOneWidget);
        expect(find.text('Any Budget'), findsOneWidget);
        expect(find.text('All Styles'), findsOneWidget);
        expect(find.text('Wedding'), findsOneWidget);
        expect(find.text('Portrait'), findsOneWidget);
      },
    );

    testWidgets(
      'PhotographerCard renders photographer details, experience, tags, price, and Book button',
      (WidgetTester tester) async {
        final samplePhotographer = {
          'id': 'photo_101',
          'display_name': 'Aura Studio',
          'category': 'Wedding',
          'city': 'Mumbai',
          'bio': 'High-fashion and luxury wedding photography.',
          'starting_price_paise': 2500000, // ₹25,000
          'experience_years': 6,
          'specializations': ['Candid', 'Cinematic'],
          'service_locations': ['Mumbai', 'Goa'],
          'availability_note': 'Available for destination weddings',
          'portfolio_urls': [
            'http://127.0.0.1:54321/storage/v1/object/public/portfolio_images/u1/1.jpg',
          ],
        };

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: PhotographerCard(
                photographer: samplePhotographer,
                onBookPressed: () {},
              ),
            ),
          ),
        );

        expect(find.text('Aura Studio'), findsOneWidget);
        expect(find.text('6Y EXP'), findsOneWidget);
        expect(find.text('Wedding • Mumbai'), findsOneWidget);
        expect(find.text('₹25000'), findsOneWidget);
        expect(find.text('Candid'), findsOneWidget);
        expect(find.text('Cinematic'), findsOneWidget);
        expect(
          find.text('Availability: Available for destination weddings'),
          findsOneWidget,
        );
        expect(find.text('Book Photographer'), findsOneWidget);
      },
    );

    testWidgets(
      'BookingDialog renders client contact fields, date picker, and estimated fee summary',
      (WidgetTester tester) async {
        final samplePhotographer = {
          'id': 'photo_101',
          'display_name': 'Aura Studio',
          'category': 'Wedding',
          'city': 'Mumbai',
          'starting_price_paise': 2000000, // ₹20,000
        };

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: BookingDialog(photographer: samplePhotographer),
            ),
          ),
        );

        expect(find.text('Reserve Session'), findsOneWidget);
        expect(find.text('Aura Studio'), findsOneWidget);
        expect(find.text('YOUR CONTACT DETAILS'), findsOneWidget);
        expect(find.text('Your Full Name'), findsOneWidget);
        expect(find.text('Your Phone Number'), findsOneWidget);
        expect(find.text('EVENT DETAILS'), findsOneWidget);
        expect(find.text('Event City'), findsOneWidget);
        expect(find.text('ESTIMATED FEE SUMMARY'), findsOneWidget);
        expect(find.text('₹20000'), findsOneWidget);
        expect(find.text('Submit Request'), findsOneWidget);
      },
    );

    testWidgets(
      'BookingCard renders client vs photographer actions correctly',
      (WidgetTester tester) async {
        final sampleBooking = {
          'id': 'b_201',
          'customer_id': 'c_1',
          'customer_name': 'Rohan Sharma',
          'customer_phone': '+919876543210',
          'event_type': 'Wedding',
          'event_city': 'Mumbai',
          'event_date': '2026-12-15',
          'status': 'accepted',
          'total_amount_paise': 2100000,
          'photographer_profiles': {'display_name': 'Aura Studio'},
        };

        // 1. Client View of Accepted Booking
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: BookingCard(
                booking: sampleBooking,
                currentUserId: 'c_1', // Current user is client
                onRefreshNeeded: () {},
                onPayDeposit: (_) {},
                onViewContactInfo: (_) {},
                onPhotographerRespond: (_, _) {},
                onCustomerCancel: (_) {},
              ),
            ),
          ),
        );

        expect(find.text('Session with Aura Studio'), findsOneWidget);
        expect(find.text('ACCEPTED'), findsOneWidget);
        expect(find.text('Pay Deposit'), findsOneWidget);
        expect(find.text('Cancel Request'), findsOneWidget);

        // 2. Photographer View of Pending Request
        final samplePendingBooking = Map<String, dynamic>.from(sampleBooking)
          ..['status'] = 'requested';

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: BookingCard(
                booking: samplePendingBooking,
                currentUserId: 'p_99', // Current user is photographer
                onRefreshNeeded: () {},
                onPayDeposit: (_) {},
                onViewContactInfo: (_) {},
                onPhotographerRespond: (_, _) {},
                onCustomerCancel: (_) {},
              ),
            ),
          ),
        );

        expect(find.text('Request from Rohan Sharma'), findsOneWidget);
        expect(find.text('Client Phone: +919876543210'), findsOneWidget);
        expect(find.text('REQUESTED'), findsOneWidget);
        expect(find.text('Accept Request'), findsOneWidget);
        expect(find.text('Decline Request'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping Pay Deposit on accepted booking shows acceptance payment prompt with Proceed to Payment and Not Now options',
      (WidgetTester tester) async {
        final sampleBooking = {
          'id': 'b_201',
          'customer_id': 'c_1',
          'customer_name': 'Rohan Sharma',
          'event_type': 'Wedding',
          'event_city': 'Mumbai',
          'event_date': '2026-12-15',
          'status': 'accepted',
          'total_amount_paise': 2100000,
          'photographer_profiles': {'display_name': 'Aura Studio'},
        };

        bool payDepositTriggered = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: BookingCard(
                booking: sampleBooking,
                currentUserId: 'c_1',
                onRefreshNeeded: () {},
                onPayDeposit: (b) {
                  payDepositTriggered = true;
                  showDialog(
                    context: tester.element(find.byType(BookingCard)),
                    builder: (ctx) => AlertDialog(
                      title: const Text('Request Accepted!'),
                      content: const Text(
                        'Your photographer has accepted your request. Would you like to proceed with payment?',
                      ),
                      actions: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Not Now'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Proceed to Payment'),
                        ),
                      ],
                    ),
                  );
                },
                onViewContactInfo: (_) {},
                onPhotographerRespond: (_, _) {},
                onCustomerCancel: (_) {},
              ),
            ),
          ),
        );

        await tester.tap(find.text('Pay Deposit'));
        await tester.pumpAndSettle();

        expect(payDepositTriggered, isTrue);
        expect(find.text('Request Accepted!'), findsOneWidget);
        expect(
          find.text(
            'Your photographer has accepted your request. Would you like to proceed with payment?',
          ),
          findsOneWidget,
        );
        expect(find.text('Not Now'), findsOneWidget);
        expect(find.text('Proceed to Payment'), findsOneWidget);

        // Tap Not Now
        await tester.tap(find.text('Not Now'));
        await tester.pumpAndSettle();

        // Dialog dismissed, card remains
        expect(find.text('Request Accepted!'), findsNothing);
        expect(find.text('ACCEPTED'), findsOneWidget);
      },
    );

    testWidgets(
      'BookingChatScreen displays locked UI when payment is unverified',
      (WidgetTester tester) async {
        final unconfirmedBooking = {
          'id': 'b_301',
          'status': 'accepted', // Unconfirmed / Payment pending
          'event_type': 'Wedding',
          'photographer_profiles': {'display_name': 'Aura Studio'},
        };

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: BookingChatScreen(booking: unconfirmedBooking),
          ),
        );

        expect(find.text('Chat Locked'), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline), findsOneWidget);
        expect(
          find.textContaining(
            'Session chat is available only after backend payment verification.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'BookingChatScreen renders messaging interface when status is confirmed',
      (WidgetTester tester) async {
        final confirmedBooking = {
          'id': 'b_302',
          'status': 'confirmed', // Confirmed & Paid
          'event_type': 'Wedding',
          'photographer_profiles': {'display_name': 'Aura Studio'},
        };

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: BookingChatScreen(booking: confirmedBooking),
          ),
        );

        expect(find.text('Session Chat — Wedding'), findsOneWidget);
        expect(find.text('With Aura Studio'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 60));
      },
    );
  });
}
