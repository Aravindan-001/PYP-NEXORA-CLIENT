import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reusable editorial empty state widget with icon, title, subtitle, and optional CTA button.
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceVariant,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.borderDark),
              ),
              child: Icon(icon, size: 40, color: AppColors.champagneGold),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.warmIvory,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.mutedSilver,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(actionLabel!),
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reusable editorial loading indicator with optional progress label.
class EditorialLoadingWidget extends StatelessWidget {
  final String? label;

  const EditorialLoadingWidget({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.champagneGold,
              ),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 16),
            Text(
              label!,
              style: const TextStyle(
                color: AppColors.mutedSilver,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Reusable editorial error state banner / card with retry button.
class EditorialErrorWidget extends StatelessWidget {
  final String errorMessage;
  final VoidCallback? onRetry;

  const EditorialErrorWidget({
    super.key,
    required this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.statusCancelled.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 40,
              color: AppColors.statusCancelled,
            ),
            const SizedBox(height: 12),
            const Text(
              'Something Went Wrong',
              style: TextStyle(
                color: AppColors.warmIvory,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.mutedSilver,
                fontSize: 13,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
