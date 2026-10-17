import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Helper model representing trusted invoice data retrieved from server.
class InvoiceData {
  final String bookingId;
  final String invoiceNumber;
  final DateTime issueDate;
  final String customerName;
  final String? customerPhone;
  final String photographerName;
  final String eventDate;
  final String eventCity;
  final String eventType;
  final int photographerFeePaise;
  final int commissionPaise;
  final int totalAmountPaise;
  final String bookingStatus;
  final String paymentStatus;
  final String? providerOrderId;
  final String? providerPaymentId;
  final DateTime? verifiedAt;

  const InvoiceData({
    required this.bookingId,
    required this.invoiceNumber,
    required this.issueDate,
    required this.customerName,
    this.customerPhone,
    required this.photographerName,
    required this.eventDate,
    required this.eventCity,
    required this.eventType,
    required this.photographerFeePaise,
    required this.commissionPaise,
    required this.totalAmountPaise,
    required this.bookingStatus,
    required this.paymentStatus,
    this.providerOrderId,
    this.providerPaymentId,
    this.verifiedAt,
  });

  factory InvoiceData.fromMap(Map<String, dynamic> map) {
    int? parsePaise(List<String> keys) {
      for (final key in keys) {
        final raw = map[key];
        if (raw is int) return raw;
        if (raw is num && raw.isFinite) return raw.toInt();
        if (raw is String) {
          final parsed = int.tryParse(raw);
          if (parsed != null) return parsed;
        }
      }
      return null;
    }

    final rawFee =
        parsePaise(['out_photographer_fee_paise', 'photographer_fee_paise']) ??
        100000;
    final rawComm =
        parsePaise(['out_commission_paise', 'commission_paise']) ??
        (rawFee * 5 / 100).round();
    final rawTotal =
        parsePaise(['out_total_amount_paise', 'total_amount_paise']) ??
        (rawFee + rawComm);
    final bookingIdStr =
        (map['out_booking_id'] ?? map['id'] ?? map['booking_id'] ?? '')
            .toString();
    final issueDateRaw = map['out_issue_date'] ?? map['created_at'];
    final issueDt = issueDateRaw != null
        ? DateTime.tryParse(issueDateRaw.toString()) ?? DateTime.now()
        : DateTime.now();

    final invNum =
        map['out_invoice_number']?.toString() ??
        'INV-${issueDt.year}${issueDt.month.toString().padLeft(2, '0')}${issueDt.day.toString().padLeft(2, '0')}-${bookingIdStr.replaceAll('-', '').substring(0, bookingIdStr.replaceAll('-', '').length < 8 ? bookingIdStr.replaceAll('-', '').length : 8).toUpperCase()}';

    final verAtRaw = map['out_verified_at'] ?? map['verified_at'];
    final verDt = verAtRaw != null
        ? DateTime.tryParse(verAtRaw.toString())
        : null;

    final photoInfo = map['photographer_profiles'] as Map<String, dynamic>?;
    final photoNameStr =
        (map['out_photographer_name'] ??
                photoInfo?['display_name'] ??
                map['photographer_name'] ??
                'Photographer')
            .toString();

    return InvoiceData(
      bookingId: bookingIdStr,
      invoiceNumber: invNum,
      issueDate: issueDt,
      customerName:
          (map['out_customer_name'] ?? map['customer_name'] ?? 'Client')
              .toString(),
      customerPhone: map['out_customer_phone'] ?? map['customer_phone'],
      photographerName: photoNameStr,
      eventDate: (map['out_event_date'] ?? map['event_date'] ?? '').toString(),
      eventCity: (map['out_event_city'] ?? map['event_city'] ?? '').toString(),
      eventType: (map['out_event_type'] ?? map['event_type'] ?? 'Session')
          .toString(),
      photographerFeePaise: rawFee,
      commissionPaise: rawComm,
      totalAmountPaise: rawTotal,
      bookingStatus: (map['out_booking_status'] ?? map['status'] ?? 'requested')
          .toString(),
      paymentStatus:
          (map['out_payment_status'] ?? map['payment_status'] ?? 'unpaid')
              .toString(),
      providerOrderId: map['out_provider_order_id'] ?? map['provider_order_id'],
      providerPaymentId:
          map['out_provider_payment_id'] ?? map['provider_payment_id'],
      verifiedAt: verDt,
    );
  }

  bool get isPaid =>
      paymentStatus == 'captured' ||
      bookingStatus == 'confirmed' ||
      bookingStatus == 'completed';

  double get photographerFeeInr => photographerFeePaise / 100.0;
  double get commissionInr => commissionPaise / 100.0;
  double get totalAmountInr => totalAmountPaise / 100.0;
}

/// Service generating and exporting PDF invoices for PYP bookings.
class InvoicePdfService {
  /// Pure PDF byte generator for an InvoiceData instance.
  static Future<Uint8List> generatePdfBytes(InvoiceData invoice) async {
    final pdf = pw.Document();

    final goldColor = PdfColor.fromHex('#C6A76A');
    final darkSurface = PdfColor.fromHex('#1E1E20');
    final textDark = PdfColor.fromHex('#111111');
    final textMuted = PdfColor.fromHex('#666666');
    final greenColor = PdfColor.fromHex('#059669');
    final amberColor = PdfColor.fromHex('#D97706');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Brand Banner
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'PYP',
                        style: pw.TextStyle(
                          fontSize: 26,
                          fontWeight: pw.FontWeight.bold,
                          color: goldColor,
                        ),
                      ),
                      pw.Text(
                        'PICK YOUR PHOTOGRAPHER',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: textMuted,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        invoice.isPaid
                            ? 'PAYMENT RECEIPT'
                            : 'PRO FORMA INVOICE',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: textDark,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Invoice #: ${invoice.invoiceNumber}',
                        style: pw.TextStyle(fontSize: 10, color: textMuted),
                      ),
                      pw.Text(
                        'Issue Date: ${invoice.issueDate.day}/${invoice.issueDate.month}/${invoice.issueDate.year}',
                        style: pw.TextStyle(fontSize: 10, color: textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(color: PdfColors.grey300, thickness: 1),
              pw.SizedBox(height: 12),

              // Status Badge Box
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: invoice.isPaid
                      ? PdfColor.fromHex('#ECFDF5')
                      : PdfColor.fromHex('#FFFBEB'),
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(
                    color: invoice.isPaid ? greenColor : amberColor,
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      invoice.isPaid
                          ? 'PAYMENT STATUS: PAID & CONFIRMED'
                          : 'PAYMENT STATUS: QUOTATION / UNPAID',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: invoice.isPaid ? greenColor : amberColor,
                      ),
                    ),
                    if (invoice.isPaid && invoice.verifiedAt != null)
                      pw.Text(
                        'Verified: ${invoice.verifiedAt!.day}/${invoice.verifiedAt!.month}/${invoice.verifiedAt!.year}',
                        style: pw.TextStyle(fontSize: 10, color: greenColor),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Customer & Photographer Info Row
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'CUSTOMER / CLIENT',
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: textMuted,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            invoice.customerName,
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: textDark,
                            ),
                          ),
                          if (invoice.customerPhone != null)
                            pw.Text(
                              'Phone: ${invoice.customerPhone}',
                              style: pw.TextStyle(
                                fontSize: 10,
                                color: textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'SERVICE PROVIDER',
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: textMuted,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            invoice.photographerName,
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                              color: textDark,
                            ),
                          ),
                          pw.Text(
                            'Location: ${invoice.eventCity}',
                            style: pw.TextStyle(fontSize: 10, color: textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Session & Event Details Box
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'SESSION & EVENT DETAILS',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: textMuted,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Event Type: ${invoice.eventType}',
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: textDark,
                          ),
                        ),
                        pw.Text(
                          'Event Date: ${invoice.eventDate}',
                          style: pw.TextStyle(fontSize: 11, color: textDark),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Booking Ref #: ${invoice.bookingId}',
                      style: pw.TextStyle(fontSize: 9, color: textMuted),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Itemized Table
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: darkSurface),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'DESCRIPTION',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'AMOUNT (INR)',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Photographer Service Quotation',
                              style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                                color: textDark,
                              ),
                            ),
                            pw.Text(
                              'Quoted session fee payable to ${invoice.photographerName}',
                              style: pw.TextStyle(
                                fontSize: 9,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'INR ${invoice.photographerFeeInr.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontSize: 11, color: textDark),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'PYP Platform Service Charge (5%)',
                              style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                                color: textDark,
                              ),
                            ),
                            pw.Text(
                              'Covers payment processing, buyer protection & platform support',
                              style: pw.TextStyle(
                                fontSize: 9,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'INR ${invoice.commissionInr.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontSize: 11, color: textDark),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),

              // Total Calculation Row
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Container(
                    width: 240,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'TOTAL PAYABLE:',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: textDark,
                          ),
                        ),
                        pw.Text(
                          'INR ${invoice.totalAmountInr.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: goldColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Payment Verification Reference (If Paid)
              if (invoice.isPaid && invoice.providerPaymentId != null)
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'VERIFIED TRANSACTION REFERENCE',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: textMuted,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Razorpay Payment ID: ${invoice.providerPaymentId}',
                        style: pw.TextStyle(fontSize: 9, color: textDark),
                      ),
                      if (invoice.providerOrderId != null)
                        pw.Text(
                          'Razorpay Order ID: ${invoice.providerOrderId}',
                          style: pw.TextStyle(fontSize: 9, color: textDark),
                        ),
                    ],
                  ),
                ),

              pw.Spacer(),

              // Footer Notice
              pw.Divider(color: PdfColors.grey300, thickness: 0.5),
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text(
                  'Thank you for using Pick Your Photographer (PYP). All fees are processed server-side in integer paise.',
                  style: pw.TextStyle(
                    fontSize: 8,
                    color: textMuted,
                    fontStyle: pw.FontStyle.italic,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Exports / Shares PDF invoice using platform Printing APIs.
  static Future<void> shareInvoicePdf(InvoiceData invoice) async {
    final pdfBytes = await generatePdfBytes(invoice);
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: '${invoice.invoiceNumber}.pdf',
    );
  }

  /// Opens native print / preview dialog for invoice.
  static Future<void> printInvoicePdf(InvoiceData invoice) async {
    final pdfBytes = await generatePdfBytes(invoice);
    await Printing.layoutPdf(
      onLayout: (_) => pdfBytes,
      name: invoice.invoiceNumber,
    );
  }
}
