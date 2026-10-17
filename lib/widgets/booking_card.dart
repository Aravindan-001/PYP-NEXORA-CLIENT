import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'invoice_dialog.dart';

/// Editorial Booking Card displaying event details, status badge, fees, and action buttons.
class BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final String currentUserId;
  final VoidCallback onRefreshNeeded;
  final Function(Map<String, dynamic>) onPayDeposit;
  final Function(String) onViewContactInfo;
  final Function(String, bool) onPhotographerRespond;
  final Function(String) onCustomerCancel;
  final Function(Map<String, dynamic>)? onOpenChat;

  const BookingCard({
    super.key,
    required this.booking,
    required this.currentUserId,
    required this.onRefreshNeeded,
    required this.onPayDeposit,
    required this.onViewContactInfo,
    required this.onPhotographerRespond,
    required this.onCustomerCancel,
    this.onOpenChat,
  });

  Color _getStatusBadgeColor(String status) {
    switch (status) {
      case 'requested':
      case 'pending':
        return AppColors.statusRequested;
      case 'accepted':
        return AppColors.statusAccepted;
      case 'awaiting_payment':
      case 'payment_pending':
        return AppColors.statusAwaitingPayment;
      case 'confirmed':
        return AppColors.statusConfirmed;
      case 'completed':
        return AppColors.statusCompleted;
      case 'cancelled':
        return AppColors.statusCancelled;
      case 'rejected':
      case 'declined':
        return AppColors.statusRejected;
      default:
        return AppColors.mutedSilver;
    }
  }

  String _formatStatusText(String status) {
    switch (status) {
      case 'requested':
      case 'pending':
        return 'REQUESTED';
      case 'awaiting_payment':
      case 'payment_pending':
        return 'PAYMENT PENDING';
      case 'rejected':
      case 'declined':
        return 'DECLINED';
      default:
        return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = booking['status'].toString();
    final isCustomer = booking['customer_id'] == currentUserId;
    final totalPaise = (booking['total_amount_paise'] as int?) ?? 100000;
    final totalINR = totalPaise / 100.0;

    final photographerInfo =
        booking['photographer_profiles'] as Map<String, dynamic>?;
    final photoName = photographerInfo?['display_name'] ?? 'Photographer';
    final custName = booking['customer_name'] ?? 'Client';
    final custPhone = booking['customer_phone'];
    final eventType = booking['event_type'] ?? 'Event';
    final eventCity = booking['event_city'] ?? 'City';
    final eventDate = booking['event_date'] ?? 'Date';
    final customerNote = booking['customer_note'];

    final badgeColor = _getStatusBadgeColor(status);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar: Event Type & Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eventType.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.champagneGold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isCustomer
                            ? 'Session with $photoName'
                            : 'Request from $custName',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.warmIvory,
                        ),
                      ),
                      if (!isCustomer &&
                          custPhone != null &&
                          custPhone.toString().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Client Phone: $custPhone',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.mutedSilver,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    _formatStatusText(status),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Metadata Row: City, Date, Fee
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceVariant,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LOCATION & DATE',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.mutedSilver,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$eventCity • $eventDate',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.warmIvory,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: AppColors.borderDark,
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'TOTAL FEE',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.mutedSilver,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${totalINR.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.champagneGold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (customerNote != null && customerNote.toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Requirements: $customerNote',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.mutedSilver,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Payment Action (for customer when accepted)
                if (isCustomer &&
                    (status == 'accepted' ||
                        status == 'awaiting_payment' ||
                        status == 'payment_pending'))
                  ElevatedButton.icon(
                    icon: const Icon(Icons.payment, size: 16),
                    label: const Text('Pay Deposit'),
                    onPressed: () => onPayDeposit(booking),
                  ),

                // Chat Action (unlocked ONLY when confirmed or completed)
                if ((status == 'confirmed' || status == 'completed') &&
                    onOpenChat != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.champagneGold,
                      foregroundColor: AppColors.obsidian,
                    ),
                    icon: const Icon(Icons.chat, size: 16),
                    label: const Text('Open Chat'),
                    onPressed: () => onOpenChat!(booking),
                  ),

                // Contact Info
                if (status == 'confirmed' || status == 'completed')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.contact_phone, size: 16),
                    label: const Text('View Contact Info'),
                    onPressed: () => onViewContactInfo(booking['id']),
                  ),

                // Invoice / Receipt Action
                OutlinedButton.icon(
                  key: Key('view_invoice_button_${booking['id']}'),
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: Text(
                    status == 'confirmed' || status == 'completed'
                        ? 'View Receipt'
                        : 'View Invoice',
                  ),
                  onPressed: () =>
                      InvoiceDialog.show(context, booking: booking),
                ),

                // Cancellation Action
                if (isCustomer &&
                    (status == 'requested' ||
                        status == 'pending' ||
                        status == 'accepted' ||
                        status == 'awaiting_payment' ||
                        status == 'payment_pending'))
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Cancel Request'),
                    onPressed: () => onCustomerCancel(booking['id']),
                  ),

                // Photographer Response Actions
                if (!isCustomer &&
                    (status == 'requested' || status == 'pending')) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.statusConfirmed,
                      foregroundColor: AppColors.warmIvory,
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Accept Request'),
                    onPressed: () => onPhotographerRespond(booking['id'], true),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.statusCancelled,
                      side: const BorderSide(color: AppColors.statusCancelled),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Decline Request'),
                    onPressed: () =>
                        onPhotographerRespond(booking['id'], false),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
