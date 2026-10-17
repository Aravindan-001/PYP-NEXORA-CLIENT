import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/app_theme.dart';
import 'empty_state_widget.dart';

/// Booking-specific messaging interface.
/// Server-authoritative RLS enforces that chat is only unlocked after backend verifies payment (status == 'confirmed' or 'completed').
class BookingChatScreen extends StatefulWidget {
  final Map<String, dynamic> booking;
  final SupabaseClient? supabaseClient;

  const BookingChatScreen({
    super.key,
    required this.booking,
    this.supabaseClient,
  });

  static void navigateTo(BuildContext context, Map<String, dynamic> booking) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BookingChatScreen(booking: booking)),
    );
  }

  @override
  State<BookingChatScreen> createState() => _BookingChatScreenState();
}

class _BookingChatScreenState extends State<BookingChatScreen> {
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  RealtimeChannel? _chatChannel;

  SupabaseClient get _supabase =>
      widget.supabaseClient ?? Supabase.instance.client;

  String get _currentUserId => _supabase.auth.currentUser?.id ?? '';

  String get _bookingId => widget.booking['id'].toString();

  String get _bookingStatus => widget.booking['status'].toString();

  bool get _isChatUnlocked =>
      _bookingStatus == 'confirmed' || _bookingStatus == 'completed';

  @override
  void initState() {
    super.initState();
    if (_isChatUnlocked) {
      _loadChatHistory();
      _subscribeToRealtimeChat();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _chatChannel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _supabase
          .from('chat_messages')
          .select()
          .eq('booking_id', _bookingId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _subscribeToRealtimeChat() {
    try {
      _chatChannel = _supabase
          .channel('chat_messages_booking_$_bookingId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'chat_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'booking_id',
              value: _bookingId,
            ),
            callback: (payload) {
              final newMsg = Map<String, dynamic>.from(payload.newRecord);
              if (mounted) {
                setState(() {
                  // Deduplicate if already added
                  if (!_messages.any((m) => m['id'] == newMsg['id'])) {
                    _messages.add(newMsg);
                  }
                });
                _scrollToBottom();
              }
            },
          )
          .subscribe();
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    setState(() => _isSending = true);

    try {
      await _supabase.rpc(
        'send_chat_message',
        params: {'p_booking_id': _bookingId, 'p_message': text},
      );
      // Reload in case realtime latency exists
      await _loadChatHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _formatTimestamp(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventType = widget.booking['event_type'] ?? 'Session';
    final photoInfo =
        widget.booking['photographer_profiles'] as Map<String, dynamic>?;
    final photoName = photoInfo?['display_name'] ?? 'Photographer';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Session Chat — $eventType',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.warmIvory,
              ),
            ),
            Text(
              'With $photoName',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.champagneGold,
              ),
            ),
          ],
        ),
      ),
      body: !_isChatUnlocked
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.darkSurfaceVariant,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.borderDark),
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        size: 48,
                        color: AppColors.champagneGold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Chat Locked',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.warmIvory,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Session chat is available only after backend payment verification.\nCurrently status is: ${_bookingStatus.toUpperCase()}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.mutedSilver,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: _isLoading
                      ? const EditorialLoadingWidget(
                          label: 'Loading chat messages...',
                        )
                      : _errorMessage != null
                      ? EditorialErrorWidget(
                          errorMessage:
                              'Error loading messages: $_errorMessage',
                          onRetry: _loadChatHistory,
                        )
                      : _messages.isEmpty
                      ? const EmptyStateWidget(
                          icon: Icons.chat_bubble_outline,
                          title: 'No Messages Yet',
                          message:
                              'Start the conversation with your photographer or client regarding session details.',
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final senderId = msg['sender_id'].toString();
                            final isMe = senderId == _currentUserId;
                            final senderName = msg['sender_name'] ?? 'User';
                            final text = msg['message'] ?? '';
                            final timeStr = _formatTimestamp(
                              msg['created_at']?.toString(),
                            );

                            return Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.75,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? AppColors.champagneGold.withValues(
                                          alpha: 0.2,
                                        )
                                      : AppColors.darkSurfaceVariant,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(14),
                                    topRight: const Radius.circular(14),
                                    bottomLeft: Radius.circular(isMe ? 14 : 2),
                                    bottomRight: Radius.circular(isMe ? 2 : 14),
                                  ),
                                  border: Border.all(
                                    color: isMe
                                        ? AppColors.champagneGold.withValues(
                                            alpha: 0.5,
                                          )
                                        : AppColors.borderDark,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!isMe)
                                      Text(
                                        senderName,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.champagneGold,
                                        ),
                                      ),
                                    if (!isMe) const SizedBox(height: 2),
                                    Text(
                                      text,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.warmIvory,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Align(
                                      alignment: Alignment.bottomRight,
                                      child: Text(
                                        timeStr,
                                        style: const TextStyle(
                                          fontSize: 9,
                                          color: AppColors.mutedSilver,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Message Input Bar
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: AppColors.obsidian,
                    border: Border(
                      top: BorderSide(color: AppColors.borderDark),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.champagneGold,
                          foregroundColor: AppColors.obsidian,
                        ),
                        icon: _isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.obsidian,
                                ),
                              )
                            : const Icon(Icons.send),
                        onPressed: _isSending ? null : _sendMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
