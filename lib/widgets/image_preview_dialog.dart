import 'package:flutter/material.dart';

/// Full-screen image preview dialog supporting zoom and optional delete/replace actions.
class ImagePreviewDialog extends StatelessWidget {
  final String imageUrl;
  final String? title;
  final VoidCallback? onDelete;
  final VoidCallback? onReplace;

  const ImagePreviewDialog({
    super.key,
    required this.imageUrl,
    this.title,
    this.onDelete,
    this.onReplace,
  });

  static void show(
    BuildContext context, {
    required String imageUrl,
    String? title,
    VoidCallback? onDelete,
    VoidCallback? onReplace,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => ImagePreviewDialog(
        imageUrl: imageUrl,
        title: title,
        onDelete: onDelete,
        onReplace: onReplace,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black.withValues(alpha: 0.92),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                          : null,
                      color: Colors.white,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white70, size: 64),
                      SizedBox(height: 12),
                      Text(
                        'Failed to load image',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  tooltip: 'Close Preview',
                  onPressed: () => Navigator.of(context).pop(),
                ),
                if (title != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Spacer(),
                if (onReplace != null)
                  IconButton(
                    icon: const Icon(
                      Icons.swap_horiz,
                      color: Colors.white,
                      size: 28,
                    ),
                    tooltip: 'Replace Photo',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onReplace?.call();
                    },
                  ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(
                      Icons.delete,
                      color: Colors.redAccent,
                      size: 28,
                    ),
                    tooltip: 'Delete Photo',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onDelete?.call();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
