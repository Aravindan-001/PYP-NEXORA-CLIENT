import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';

/// Responsive, polished booking modal dialog for selecting dates, event city,
/// event type, and submitting booking requests.
class BookingDialog extends StatefulWidget {
  final Map<String, dynamic> photographer;
  final SupabaseClient? supabaseClient;

  const BookingDialog({
    super.key,
    required this.photographer,
    this.supabaseClient,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Map<String, dynamic> photographer,
    SupabaseClient? supabaseClient,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => BookingDialog(
        photographer: photographer,
        supabaseClient: supabaseClient,
      ),
    );
  }

  @override
  State<BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<BookingDialog> {
  late final TextEditingController _cityController;
  late final TextEditingController _typeController;
  late final TextEditingController _noteController;
  late DateTime _selectedDate;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _cityController = TextEditingController(
      text: widget.photographer['city'] ?? '',
    );
    _typeController = TextEditingController(
      text: widget.photographer['category'] ?? '',
    );
    _noteController = TextEditingController();
    _selectedDate = DateTime.now().add(const Duration(days: 7));
  }

  @override
  void dispose() {
    _cityController.dispose();
    _typeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  SupabaseClient get _supabase =>
      widget.supabaseClient ?? Supabase.instance.client;

  Future<void> _submitBooking() async {
    final city = _cityController.text.trim();
    final type = _typeController.text.trim();
    final note = _noteController.text.trim();

    if (city.isEmpty || type.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event City and Event Type are required.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final photographerId = widget.photographer['id'];
      final formattedDate = _selectedDate.toIso8601String().split('T')[0];

      await _supabase.rpc(
        'create_booking_request',
        params: {
          'p_photographer_id': photographerId,
          'p_event_date': formattedDate,
          'p_event_city': city,
          'p_event_type': type,
          'p_customer_note': note.isNotEmpty ? note : null,
        },
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Booking request submitted! Check My Bookings for updates.',
            ),
            backgroundColor: AppColors.statusConfirmed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Booking failed: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.photographer['display_name'] ?? 'Photographer';
    final pricePaise =
        (widget.photographer['starting_price_paise'] as int?) ?? 100000;
    final feeINR = pricePaise / 100.0;
    final commissionINR = (feeINR * 0.05);
    final totalINR = feeINR + commissionINR;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dialog Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.darkSurfaceVariant,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.calendar_today,
                      color: AppColors.champagneGold,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reserve Session',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.champagneGold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.warmIvory,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.mutedSilver),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Form fields
              TextField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'Event City',
                  prefixIcon: Icon(
                    Icons.location_city,
                    color: AppColors.mutedSilver,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _typeController,
                decoration: const InputDecoration(
                  labelText: 'Event Type (e.g. Wedding, Portrait)',
                  prefixIcon: Icon(
                    Icons.category,
                    color: AppColors.mutedSilver,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Special Requests / Notes (Optional)',
                  prefixIcon: Icon(Icons.notes, color: AppColors.mutedSilver),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Date Picker Field
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: AppColors.champagneGold,
                            onPrimary: AppColors.obsidian,
                            surface: AppColors.darkSurface,
                            onSurface: AppColors.warmIvory,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderDark),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event,
                        color: AppColors.champagneGold,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Selected Event Date',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.mutedSilver,
                              ),
                            ),
                            Text(
                              _selectedDate.toIso8601String().split('T')[0],
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warmIvory,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Text(
                        'Change',
                        style: TextStyle(
                          color: AppColors.champagneGold,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Estimated Fee Breakdown
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
                      'ESTIMATED FEE SUMMARY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.mutedSilver,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Photographer Fee',
                          style: TextStyle(
                            color: AppColors.warmIvory,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '₹${feeINR.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.warmIvory,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Platform Service (5%)',
                          style: TextStyle(
                            color: AppColors.mutedSilver,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '₹${commissionINR.toStringAsFixed(0)}',
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
                          'Estimated Deposit Total',
                          style: TextStyle(
                            color: AppColors.warmIvory,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '₹${totalINR.toStringAsFixed(0)}',
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
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _isSubmitting
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : ElevatedButton(
                            onPressed: _submitBooking,
                            child: const Text('Submit Request'),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
