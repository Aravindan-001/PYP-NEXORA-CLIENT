import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/portfolio_service.dart';
import '../theme/app_theme.dart';
import 'image_preview_dialog.dart';

/// Widget that allows authenticated photographers to manage (upload, preview, replace, delete)
/// their portfolio showcase images.
class PortfolioManagerWidget extends StatefulWidget {
  final List<String> initialPortfolioUrls;
  final ValueChanged<List<String>>? onPortfolioUpdated;
  final SupabaseClient? supabaseClient;
  final PortfolioService? portfolioService;

  const PortfolioManagerWidget({
    super.key,
    required this.initialPortfolioUrls,
    this.onPortfolioUpdated,
    this.supabaseClient,
    this.portfolioService,
  });

  @override
  State<PortfolioManagerWidget> createState() => _PortfolioManagerWidgetState();
}

class _PortfolioManagerWidgetState extends State<PortfolioManagerWidget> {
  late List<String> _portfolioUrls;
  late final PortfolioService _service;

  bool _isUploading = false;
  String? _uploadStatusText;
  String? _errorMessage;

  // Store failed upload details for retry capability
  Uint8List? _lastFailedBytes;
  String? _lastFailedFileName;
  int? _replaceIndexTarget;

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
    _portfolioUrls = List.from(widget.initialPortfolioUrls);
    _service = widget.portfolioService ?? PortfolioService();
  }

  @override
  void didUpdateWidget(PortfolioManagerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPortfolioUrls != oldWidget.initialPortfolioUrls) {
      setState(() {
        _portfolioUrls = List.from(widget.initialPortfolioUrls);
      });
    }
  }

  /// Picks an image from device gallery using [ImagePicker].
  Future<void> _pickAndUploadImage({int? replaceIndex}) async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );

      if (file == null) return; // User cancelled picker

      final bytes = await file.readAsBytes();
      final fileName = file.name;

      await _uploadBytes(
        bytes: bytes,
        fileName: fileName,
        replaceIndex: replaceIndex,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to select image: $e';
        });
      }
    }
  }

  /// Validates and uploads raw image bytes to Supabase Storage.
  Future<void> _uploadBytes({
    required Uint8List bytes,
    required String fileName,
    int? replaceIndex,
  }) async {
    final client = _supabaseClient;
    final userId = client?.auth.currentUser?.id;
    if (userId == null || client == null) {
      setState(
        () => _errorMessage = 'Please sign in to upload portfolio images.',
      );
      return;
    }

    // Preserve state for retry if needed
    _lastFailedBytes = bytes;
    _lastFailedFileName = fileName;
    _replaceIndexTarget = replaceIndex;

    setState(() {
      _isUploading = true;
      _uploadStatusText = replaceIndex != null
          ? 'Replacing photo...'
          : 'Uploading photo...';
      _errorMessage = null;
    });

    try {
      // 1. Upload new image to storage
      final newUrl = await _service.uploadPortfolioImage(
        client: client,
        bytes: bytes,
        fileName: fileName,
        userId: userId,
      );

      final updatedList = List<String>.from(_portfolioUrls);
      String? oldUrlToDelete;

      if (replaceIndex != null &&
          replaceIndex >= 0 &&
          replaceIndex < updatedList.length) {
        oldUrlToDelete = updatedList[replaceIndex];
        updatedList[replaceIndex] = newUrl;
      } else {
        if (!updatedList.contains(newUrl)) {
          updatedList.add(newUrl);
        }
      }

      // 2. Persist updated URLs to photographer_profiles schema
      List<String> savedUrls;
      try {
        savedUrls = await _service.savePortfolioUrls(
          client: client,
          portfolioUrls: updatedList,
          userId: userId,
        );
      } catch (saveError) {
        // Cleanup newly uploaded image from storage if DB persistence fails to prevent orphaned file
        try {
          await _service.deletePortfolioImage(
            client: client,
            url: newUrl,
            userId: userId,
          );
        } catch (_) {
          // Cleanup best-effort
        }
        rethrow;
      }

      // 3. Clean up old image file from storage if replaced
      if (oldUrlToDelete != null) {
        try {
          await _service.deletePortfolioImage(
            client: client,
            url: oldUrlToDelete,
            userId: userId,
          );
        } catch (_) {
          // Non-critical cleanup failure
        }
      }

      if (mounted) {
        setState(() {
          _portfolioUrls = savedUrls;
          _isUploading = false;
          _uploadStatusText = null;
          _lastFailedBytes = null;
          _lastFailedFileName = null;
          _replaceIndexTarget = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              replaceIndex != null
                  ? 'Photo replaced successfully!'
                  : 'Photo uploaded successfully!',
            ),
            backgroundColor: AppColors.statusConfirmed,
            duration: const Duration(seconds: 2),
          ),
        );

        widget.onPortfolioUpdated?.call(_portfolioUrls);
      }
    } on PortfolioValidationException catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatusText = null;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatusText = null;
          _errorMessage = 'Upload failed: $e';
        });
      }
    }
  }

  /// Retries the last failed upload attempt.
  void _retryLastUpload() {
    if (_lastFailedBytes != null && _lastFailedFileName != null) {
      _uploadBytes(
        bytes: _lastFailedBytes!,
        fileName: _lastFailedFileName!,
        replaceIndex: _replaceIndexTarget,
      );
    }
  }

  /// Prompts confirmation and deletes an image from portfolio.
  Future<void> _confirmAndDeleteImage(int index) async {
    if (index < 0 || index >= _portfolioUrls.length) return;
    final targetUrl = _portfolioUrls[index];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Portfolio Photo'),
        content: const Text(
          'Are you sure you want to remove this image from your portfolio?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusCancelled,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final client = _supabaseClient;
    final userId = client?.auth.currentUser?.id;
    if (userId == null || client == null) return;

    setState(() {
      _isUploading = true;
      _uploadStatusText = 'Deleting photo...';
      _errorMessage = null;
    });

    try {
      final updatedList = List<String>.from(_portfolioUrls)..removeAt(index);

      // Save updated URLs to profile table
      final savedUrls = await _service.savePortfolioUrls(
        client: client,
        portfolioUrls: updatedList,
        userId: userId,
      );

      // Remove from storage bucket
      await _service.deletePortfolioImage(
        client: client,
        url: targetUrl,
        userId: userId,
      );

      if (mounted) {
        setState(() {
          _portfolioUrls = savedUrls;
          _isUploading = false;
          _uploadStatusText = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo deleted from portfolio.'),
            duration: Duration(seconds: 2),
          ),
        );

        widget.onPortfolioUpdated?.call(_portfolioUrls);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadStatusText = null;
          _errorMessage = 'Failed to delete photo: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.collections,
                  color: AppColors.champagneGold,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Portfolio Showcase (${_portfolioUrls.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.warmIvory,
                  ),
                ),
              ],
            ),
            if (!_isUploading)
              ElevatedButton.icon(
                key: const Key('add_portfolio_photo_button'),
                icon: const Icon(Icons.add_a_photo, size: 16),
                label: const Text('Add Photo'),
                onPressed: () => _pickAndUploadImage(),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Error message banner with Retry option
        if (_errorMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.darkSurfaceVariant,
              border: Border.all(
                color: AppColors.statusCancelled.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.statusCancelled,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: AppColors.statusCancelled,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (_lastFailedBytes != null)
                  TextButton.icon(
                    key: const Key('retry_upload_button'),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                    onPressed: _retryLastUpload,
                  ),
              ],
            ),
          ),

        // Uploading / Deleting status indicator
        if (_isUploading)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.darkSurfaceVariant,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.champagneGold.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.champagneGold,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _uploadStatusText ?? 'Processing image...',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: AppColors.champagneGold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

        // Empty Portfolio Placeholder Card
        if (_portfolioUrls.isEmpty && !_isUploading)
          Card(
            elevation: 0,
            color: AppColors.darkSurfaceVariant,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.borderDark),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 44,
                      color: AppColors.champagneGold,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No Portfolio Photos Uploaded Yet',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.warmIvory,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Upload high-quality samples of your work to attract potential clients.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.mutedSilver,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      key: const Key('empty_portfolio_upload_button'),
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Upload Your First Photo'),
                      onPressed: () => _pickAndUploadImage(),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Portfolio Image Grid
        if (_portfolioUrls.isNotEmpty)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _portfolioUrls.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              final url = _portfolioUrls[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.champagneGold,
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: AppColors.darkSurfaceVariant,
                          child: const Icon(
                            Icons.broken_image,
                            color: AppColors.mutedSilver,
                          ),
                        );
                      },
                    ),
                    // Action Buttons Gradient Overlay
                    Positioned.fill(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => ImagePreviewDialog.show(
                            context,
                            imageUrl: url,
                            title: 'Portfolio Photo ${index + 1}',
                            onReplace: _isUploading
                                ? null
                                : () =>
                                      _pickAndUploadImage(replaceIndex: index),
                            onDelete: _isUploading
                                ? null
                                : () => _confirmAndDeleteImage(index),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.4),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.6),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Replace & Delete Quick Control Icons
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            key: Key('replace_photo_button_$index'),
                            onTap: _isUploading
                                ? null
                                : () =>
                                      _pickAndUploadImage(replaceIndex: index),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.swap_horiz,
                                color: AppColors.warmIvory,
                                size: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            key: Key('delete_photo_button_$index'),
                            onTap: _isUploading
                                ? null
                                : () => _confirmAndDeleteImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.delete,
                                color: AppColors.statusCancelled,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
