import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'portfolio_viewer_widget.dart';

/// Editorial Photographer Card for Discover Screen displaying portfolio imagery,
/// category, city, bio, starting price in INR, and booking CTA.
class PhotographerCard extends StatelessWidget {
  final Map<String, dynamic> photographer;
  final VoidCallback onBookPressed;

  const PhotographerCard({
    super.key,
    required this.photographer,
    required this.onBookPressed,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = photographer['display_name'] ?? 'Unnamed Photographer';
    final category = photographer['category'] ?? 'Photography';
    final city = photographer['city'] ?? 'Location';
    final bio = photographer['bio'] ?? '';
    final pricePaise = (photographer['starting_price_paise'] as int?) ?? 100000;
    final priceINR = pricePaise / 100.0;
    final portfolioUrls = List<String>.from(
      photographer['portfolio_urls'] ?? [],
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Avatar, Name, Category/City, Price
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.champagneGold,
                  child: Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'P',
                    style: const TextStyle(
                      color: AppColors.obsidian,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.warmIvory,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 14,
                            color: AppColors.champagneGold,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$category • $city',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.mutedSilver,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'STARTING AT',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.mutedSilver,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${priceINR.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: AppColors.champagneGold,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            if (bio.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                bio,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.warmIvory,
                  height: 1.3,
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Portfolio Showcase Preview Section
            PortfolioViewerWidget(
              portfolioUrls: portfolioUrls,
              photographerName: displayName,
            ),

            const SizedBox(height: 16),

            // Action CTA
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.event_available, size: 18),
                label: const Text('Book Photographer'),
                onPressed: onBookPressed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
