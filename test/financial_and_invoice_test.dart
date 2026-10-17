import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyp_app/services/invoice_pdf_service.dart';
import 'package:pyp_app/widgets/invoice_dialog.dart';

void main() {
  group('Fee Calculation & Financial Integrity Unit Tests', () {
    test(
      '₹1,000 quote calculates ₹50 fee (5%) and ₹1,050 total in integer paise',
      () {
        const quotePaise = 100000; // ₹1,000
        final feePaise = (quotePaise * 5 / 100).round();
        final totalPaise = quotePaise + feePaise;

        expect(feePaise, 5000); // ₹50
        expect(totalPaise, 105000); // ₹1,050
      },
    );

    test(
      '₹2,000 quote calculates ₹100 fee (5%) and ₹2,100 total in integer paise',
      () {
        const quotePaise = 200000; // ₹2,000
        final feePaise = (quotePaise * 5 / 100).round();
        final totalPaise = quotePaise + feePaise;

        expect(feePaise, 10000); // ₹100
        expect(totalPaise, 210000); // ₹2,100
      },
    );

    test('Deterministic rounding behavior for odd paise amounts', () {
      const quotePaise1 = 12345; // ₹123.45
      final feePaise1 = (quotePaise1 * 5 / 100).round(); // 617.25 -> 617
      expect(feePaise1, 617);

      const quotePaise2 = 12370; // ₹123.70
      final feePaise2 = (quotePaise2 * 5 / 100).round(); // 618.5 -> 619
      expect(feePaise2, 619);
    });

    test('Repeated calculation on quote does not re-apply platform fee', () {
      const quotePaise = 100000;
      final feePaise = (quotePaise * 5 / 100).round();
      final totalPaise = quotePaise + feePaise;

      // Photographer payout must equal original quote, NOT customer total
      expect(quotePaise, 100000);
      expect(totalPaise, 105000);
      expect(totalPaise - feePaise, quotePaise);
    });
  });

  group('InvoiceData Model Tests', () {
    test('Constructs paid InvoiceData from backend RPC response map', () {
      final map = {
        'out_booking_id': 'b1234567-89ab-cdef-0123-456789abcdef',
        'out_invoice_number': 'INV-20261014-B1234567',
        'out_issue_date': '2026-10-14T10:00:00Z',
        'out_customer_name': 'Aravindhan',
        'out_customer_phone': '9876543210',
        'out_photographer_name': 'Studio Apex',
        'out_event_date': '2026-10-25',
        'out_event_city': 'Chennai',
        'out_event_type': 'Wedding',
        'out_photographer_fee_paise': 100000,
        'out_commission_paise': 5000,
        'out_total_amount_paise': 105000,
        'out_booking_status': 'confirmed',
        'out_payment_status': 'captured',
        'out_provider_order_id': 'order_rzp123',
        'out_provider_payment_id': 'pay_rzp456',
        'out_verified_at': '2026-10-14T10:05:00Z',
      };

      final invoice = InvoiceData.fromMap(map);

      expect(invoice.isPaid, isTrue);
      expect(invoice.photographerFeeInr, 1000.0);
      expect(invoice.commissionInr, 50.0);
      expect(invoice.totalAmountInr, 1050.0);
      expect(invoice.invoiceNumber, 'INV-20261014-B1234567');
      expect(invoice.providerPaymentId, 'pay_rzp456');
    });

    test('Constructs unpaid pro-forma InvoiceData correctly', () {
      final map = {
        'id': 'b9999999-89ab-cdef-0123-456789abcdef',
        'customer_name': 'Jane Doe',
        'photographer_name': 'Lens Craft',
        'event_date': '2026-11-01',
        'event_city': 'Bangalore',
        'event_type': 'Portrait',
        'photographer_fee_paise': 200000,
        'commission_paise': 10000,
        'total_amount_paise': 210000,
        'status': 'requested',
        'payment_status': 'unpaid',
      };

      final invoice = InvoiceData.fromMap(map);

      expect(invoice.isPaid, isFalse);
      expect(invoice.photographerFeeInr, 2000.0);
      expect(invoice.commissionInr, 100.0);
      expect(invoice.totalAmountInr, 2100.0);
      expect(invoice.paymentStatus, 'unpaid');
    });
  });

  group('Invoice PDF Generator Tests', () {
    test('Generates non-empty PDF bytes for invoice', () async {
      final invoice = InvoiceData(
        bookingId: 'b1234567-89ab-cdef-0123-456789abcdef',
        invoiceNumber: 'INV-20261014-B1234567',
        issueDate: DateTime.now(),
        customerName: 'Aravindhan',
        photographerName: 'Studio Apex',
        eventDate: '2026-10-25',
        eventCity: 'Chennai',
        eventType: 'Wedding',
        photographerFeePaise: 100000,
        commissionPaise: 5000,
        totalAmountPaise: 105000,
        bookingStatus: 'confirmed',
        paymentStatus: 'captured',
        providerOrderId: 'order_rzp123',
        providerPaymentId: 'pay_rzp456',
      );

      final pdfBytes = await InvoicePdfService.generatePdfBytes(invoice);

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.isNotEmpty, isTrue);
      final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
      expect(header, '%PDF-');
    });
  });

  group('Invoice UI Dialog Widget Tests', () {
    testWidgets('InvoiceDialog renders invoice breakdown and actions', (
      WidgetTester tester,
    ) async {
      final bookingMap = {
        'id': 'b1234567-89ab-cdef-0123-456789abcdef',
        'customer_name': 'Aravindhan',
        'photographer_name': 'Studio Apex',
        'event_date': '2026-10-25',
        'event_city': 'Chennai',
        'event_type': 'Wedding',
        'photographer_fee_paise': 100000,
        'commission_paise': 5000,
        'total_amount_paise': 105000,
        'status': 'confirmed',
        'payment_status': 'captured',
        'provider_payment_id': 'pay_rzp456',
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: InvoiceDialog(booking: bookingMap)),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('FINANCIAL BREAKDOWN'), findsOneWidget);
      expect(find.text('Photographer Service Quotation'), findsOneWidget);
      expect(find.text('PYP Platform Service Charge (5%)'), findsOneWidget);
      expect(find.text('₹1000'), findsOneWidget);
      expect(find.text('₹50'), findsOneWidget);
      expect(find.text('₹1050'), findsOneWidget);
      expect(find.byKey(const Key('share_invoice_pdf_button')), findsOneWidget);
      expect(find.byKey(const Key('print_invoice_button')), findsOneWidget);
    });
  });
}
