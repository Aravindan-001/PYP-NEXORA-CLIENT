import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/invoice_pdf_service.dart';
import '../theme/app_theme.dart';
import 'empty_state_widget.dart';

/// Modal dialog allowing authorized users to view, generate, print, or share
/// PDF invoices and pro-forma quotations.
class InvoiceDialog extends StatefulWidget {
  final Map<String, dynamic> booking;
  final SupabaseClient? supabaseClient;

  const InvoiceDialog({super.key, required this.booking, this.supabaseClient});

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> booking,
    SupabaseClient? supabaseClient,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) =>
          InvoiceDialog(booking: booking, supabaseClient: supabaseClient),
    );
  }

  @override
  State<InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<InvoiceDialog> {
  late Future<InvoiceData> _invoiceFuture;

  SupabaseClient? get _supabaseClient {
    if (widget.supabaseClient != null) return widget.supabaseClient;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchInvoiceData();
  }

  void _fetchInvoiceData() {
    setState(() {
      _invoiceFuture = _loadInvoiceFromRpc();
    });
  }

  Future<InvoiceData> _loadInvoiceFromRpc() async {
    final bookingId = (widget.booking['id'] ?? widget.booking['out_id'] ?? '')
        .toString()
        .trim();

    final client = _supabaseClient;
    if (client != null && bookingId.isNotEmpty) {
      try {
        final res = await client.rpc(
          'get_booking_invoice_data',
          params: {'p_booking_id': bookingId},
        );

        if (res is List && res.isNotEmpty) {
          return InvoiceData.fromMap(Map<String, dynamic>.from(res.first));
        }
      } catch (_) {
        // Fallback to widget.booking map
      }
    }

    return InvoiceData.fromMap(widget.booking);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 540),
        padding: const EdgeInsets.all(24.0),
        child: FutureBuilder<InvoiceData>(
          future: _invoiceFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const EditorialLoadingWidget(
                label: 'Generating authoritative invoice...',
              );
            }

            if (snapshot.hasError) {
              return EditorialErrorWidget(
                errorMessage: 'Failed to load invoice: ${snapshot.error}',
                onRetry: _fetchInvoiceData,
              );
            }

            final invoice = snapshot.data!;

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dialog Top Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.darkSurfaceVariant,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.borderDark),
                            ),
                            child: const Icon(
                              Icons.receipt_long,
                              color: AppColors.champagneGold,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                invoice.isPaid
                                    ? 'PAYMENT RECEIPT'
                                    : 'PRO FORMA QUOTATION',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.champagneGold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Text(
                                invoice.invoiceNumber,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.warmIvory,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.mutedSilver,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Payment Status Box
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: invoice.isPaid
                          ? AppColors.statusConfirmed.withValues(alpha: 0.12)
                          : AppColors.statusRequested.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: invoice.isPaid
                            ? AppColors.statusConfirmed.withValues(alpha: 0.4)
                            : AppColors.statusRequested.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          invoice.isPaid ? Icons.verified : Icons.info_outline,
                          color: invoice.isPaid
                              ? AppColors.statusConfirmed
                              : AppColors.statusRequested,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                invoice.isPaid
                                    ? 'PAYMENT STATUS: PAID & CONFIRMED'
                                    : 'PAYMENT STATUS: UNPAID / QUOTATION',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: invoice.isPaid
                                      ? AppColors.statusConfirmed
                                      : AppColors.statusRequested,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              Text(
                                invoice.isPaid
                                    ? 'Verified server-side via Razorpay'
                                    : 'Deposit payment required to confirm booking',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.mutedSilver,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Customer & Photographer Cards
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.darkSurfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderDark),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CLIENT DETAILS',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.mutedSilver,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                invoice.customerName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.warmIvory,
                                ),
                              ),
                              if (invoice.customerPhone != null)
                                Text(
                                  invoice.customerPhone!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.mutedSilver,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.darkSurfaceVariant,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borderDark),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'SERVICE PROVIDER',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.mutedSilver,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                invoice.photographerName,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.warmIvory,
                                ),
                              ),
                              Text(
                                invoice.eventCity,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.mutedSilver,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Session Details
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.darkSurfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'EVENT TYPE',
                              style: TextStyle(
                                fontSize: 9,
                                color: AppColors.mutedSilver,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              invoice.eventType,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warmIvory,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'EVENT DATE',
                              style: TextStyle(
                                fontSize: 9,
                                color: AppColors.mutedSilver,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              invoice.eventDate,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warmIvory,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Financial Breakdown
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.obsidian,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FINANCIAL BREAKDOWN',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppColors.champagneGold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'Photographer Service Quotation',
                                style: TextStyle(
                                  color: AppColors.warmIvory,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              '₹${invoice.photographerFeeInr.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: AppColors.warmIvory,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                'PYP Platform Service Charge (5%)',
                                style: TextStyle(
                                  color: AppColors.mutedSilver,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              '₹${invoice.commissionInr.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: AppColors.mutedSilver,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: AppColors.borderDark, height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Amount Payable',
                              style: TextStyle(
                                color: AppColors.warmIvory,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '₹${invoice.totalAmountInr.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: AppColors.champagneGold,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (invoice.isPaid && invoice.providerPaymentId != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'RAZORPAY TRANSACTION REFERENCE',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.mutedSilver,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Payment ID: ${invoice.providerPaymentId}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.warmIvory,
                            ),
                          ),
                          if (invoice.providerOrderId != null)
                            Text(
                              'Order ID: ${invoice.providerOrderId}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.mutedSilver,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Actions: Print / Share PDF
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('print_invoice_button'),
                          icon: const Icon(Icons.print, size: 16),
                          label: const Text('Print'),
                          onPressed: () =>
                              InvoicePdfService.printInvoicePdf(invoice),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          key: const Key('share_invoice_pdf_button'),
                          icon: const Icon(Icons.picture_as_pdf, size: 16),
                          label: const Text('Share PDF'),
                          onPressed: () =>
                              InvoicePdfService.shareInvoicePdf(invoice),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
