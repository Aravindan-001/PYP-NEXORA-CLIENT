import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'empty_state_widget.dart';

/// Persistent AppBar icon with unread badge and notification modal sheet.
class NotificationsWidget extends StatefulWidget {
  final SupabaseClient? supabaseClient;

  const NotificationsWidget({super.key, this.supabaseClient});

  @override
  State<NotificationsWidget> createState() => _NotificationsWidgetState();
}

class _NotificationsWidgetState extends State<NotificationsWidget> {
  int _unreadCount = 0;
  RealtimeChannel? _notifChannel;

  SupabaseClient get _supabase =>
      widget.supabaseClient ?? Supabase.instance.client;

  String get _currentUserId => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _fetchUnreadCount();
    _subscribeToNotifications();
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchUnreadCount() async {
    if (_currentUserId.isEmpty) return;
    try {
      final res = await _supabase
          .from('notifications')
          .select('id')
          .eq('user_id', _currentUserId)
          .eq('is_read', false);

      if (mounted) {
        setState(() {
          _unreadCount = (res as List).length;
        });
      }
    } catch (_) {}
  }

  void _subscribeToNotifications() {
    if (_currentUserId.isEmpty) return;
    try {
      _notifChannel = _supabase
          .channel('notifications_user_$_currentUserId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: _currentUserId,
            ),
            callback: (_) {
              _fetchUnreadCount();
            },
          )
          .subscribe();
    } catch (_) {}
  }

  void _showNotificationsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => NotificationsSheet(
        supabaseClient: _supabase,
        onNotificationsRead: _fetchUnreadCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(
            Icons.notifications_outlined,
            color: AppColors.mutedSilver,
          ),
          tooltip: 'Notifications',
          onPressed: _showNotificationsSheet,
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.champagneGold,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                _unreadCount > 9 ? '9+' : '$_unreadCount',
                style: const TextStyle(
                  color: AppColors.obsidian,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

/// Modal bottom sheet displaying notification history and mark-as-read controls.
class NotificationsSheet extends StatefulWidget {
  final SupabaseClient supabaseClient;
  final VoidCallback onNotificationsRead;

  const NotificationsSheet({
    super.key,
    required this.supabaseClient,
    required this.onNotificationsRead,
  });

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  late Future<List<Map<String, dynamic>>> _notifsFuture;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<List<Map<String, dynamic>>> _getNotifications() async {
    final userId = widget.supabaseClient.auth.currentUser?.id;
    if (userId == null) return [];
    final data = await widget.supabaseClient
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  void _fetchNotifications() {
    setState(() {
      _notifsFuture = _getNotifications();
    });
  }

  Future<void> _markAllRead() async {
    try {
      await widget.supabaseClient.rpc('mark_notifications_read');
      widget.onNotificationsRead();
      _fetchNotifications();
    } catch (_) {}
  }

  Future<void> _markSingleRead(String id) async {
    try {
      await widget.supabaseClient.rpc(
        'mark_notifications_read',
        params: {'p_notification_id': id},
      );
      widget.onNotificationsRead();
      _fetchNotifications();
    } catch (_) {}
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'booking_request':
        return Icons.event_available;
      case 'booking_accepted':
        return Icons.check_circle_outline;
      case 'booking_declined':
        return Icons.cancel_outlined;
      case 'payment_confirmed':
        return Icons.verified_user;
      case 'chat':
        return Icons.chat_bubble_outline;
      default:
        return Icons.notifications;
    }
  }

  String _formatDate(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.notifications,
                    color: AppColors.champagneGold,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.warmIvory,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                icon: const Icon(Icons.done_all, size: 16),
                label: const Text('Mark all read'),
                onPressed: _markAllRead,
              ),
            ],
          ),
          const Divider(color: AppColors.borderDark, height: 20),

          // Notifications List
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _notifsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const EditorialLoadingWidget(
                    label: 'Loading notifications...',
                  );
                }
                if (snapshot.hasError) {
                  return EditorialErrorWidget(
                    errorMessage: 'Error: ${snapshot.error}',
                    onRetry: _fetchNotifications,
                  );
                }

                final notifs = snapshot.data ?? [];
                if (notifs.isEmpty) {
                  return const EmptyStateWidget(
                    icon: Icons.notifications_none,
                    title: 'No Notifications',
                    message: 'You have no notifications at this time.',
                  );
                }

                return ListView.builder(
                  itemCount: notifs.length,
                  itemBuilder: (context, index) {
                    final n = notifs[index];
                    final id = n['id'].toString();
                    final title = n['title'] ?? 'Notification';
                    final message = n['message'] ?? '';
                    final type = n['type'] ?? 'general';
                    final isRead = n['is_read'] == true;
                    final timeStr = _formatDate(n['created_at']?.toString());

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      color: isRead
                          ? AppColors.darkSurfaceVariant.withValues(alpha: 0.5)
                          : AppColors.darkSurfaceVariant,
                      child: ListTile(
                        onTap: () => _markSingleRead(id),
                        leading: CircleAvatar(
                          backgroundColor: isRead
                              ? AppColors.darkSurface
                              : AppColors.champagneGold.withValues(alpha: 0.2),
                          child: Icon(
                            _getNotificationIcon(type),
                            color: AppColors.champagneGold,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isRead
                                ? FontWeight.normal
                                : FontWeight.bold,
                            color: AppColors.warmIvory,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              message,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.mutedSilver,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.warmIvoryDark,
                              ),
                            ),
                          ],
                        ),
                        trailing: !isRead
                            ? Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.champagneGold,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
