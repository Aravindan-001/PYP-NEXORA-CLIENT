import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'notifications_widget.dart';

/// Reusable, responsive app bar header for PYP Marketplace.
/// Displays PYP logo asset with BoxFit.contain (no cropping or distortion),
/// active screen title/subtitle, persistent notification bell,
/// username with text truncation, CUSTOMER/PHOTOGRAPHER/ADMIN role badges,
/// and sign-out control.
class PYPAppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final Set<String> userRoles;
  final String userEmail;
  final VoidCallback onSignOut;
  final List<Widget>? extraActions;
  final PreferredSizeWidget? bottom;

  const PYPAppHeader({
    super.key,
    this.title = '',
    required this.userRoles,
    required this.userEmail,
    required this.onSignOut,
    this.extraActions,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0.0));

  @override
  Widget build(BuildContext context) {
    final displayName = userEmail.contains('@')
        ? userEmail.split('@').first
        : userEmail;

    return AppBar(
      titleSpacing: 12,
      automaticallyImplyLeading: false,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dedicated Logo Asset Area (BoxFit.contain, 1:1 aspect ratio, no cropping)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 38,
              height: 38,
              color: AppColors.darkSurfaceVariant,
              child: Image.asset(
                'assets/images/pyp_logo.jpeg',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.camera_alt,
                  color: AppColors.champagneGold,
                  size: 24,
                ),
              ),
            ),
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: AppColors.champagneGold,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ],
      ),
      actions: [
        ...?extraActions,

        // Persistent Notification Bell with Unread Badge
        const NotificationsWidget(),

        // User Name & Role Badges Stacked Responsively
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 140),
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.warmIvory,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: userRoles.map((role) {
                      final isRoleAdmin = role == 'admin';
                      final isRolePhoto = role == 'photographer';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        margin: const EdgeInsets.only(left: 3),
                        decoration: BoxDecoration(
                          color: isRoleAdmin || isRolePhoto
                              ? AppColors.champagneGold.withValues(alpha: 0.2)
                              : AppColors.darkSurfaceVariant,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isRoleAdmin || isRolePhoto
                                ? AppColors.champagneGold
                                : AppColors.borderDark,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          role.toUpperCase(),
                          style: TextStyle(
                            fontSize: 8,
                            color: isRoleAdmin || isRolePhoto
                                ? AppColors.champagneGold
                                : AppColors.mutedSilver,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Sign Out Action Button
        IconButton(
          icon: const Icon(
            Icons.logout,
            color: AppColors.mutedSilver,
            size: 20,
          ),
          tooltip: 'Sign Out',
          visualDensity: VisualDensity.compact,
          onPressed: onSignOut,
        ),
        const SizedBox(width: 4),
      ],
      bottom: bottom,
    );
  }
}
