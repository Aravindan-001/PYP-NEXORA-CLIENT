import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'portfolio_viewer_widget.dart';

/// Editorial Photographer Card for Discover Screen displaying portfolio imagery,
/// category, city, experience, specializations, service locations, availability,
/// starting price in INR, and booking CTA.
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
    final experienceYears = (photographer['experience_years'] as int?) ?? 0;
    final specializations = List<String>.from(
      photographer['specializations'] ?? [],
    );
    final serviceLocations = List<String>.from(
      photographer['service_locations'] ?? [],
    );
    final availabilityNote = photographer['availability_note']?.toString();
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warmIvory,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (experienceYears > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.champagneGold.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.champagneGold.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Text(
                                '${experienceYears}Y EXP',
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.champagneGold,
                                ),
                              ),
                            ),
                          ],
                        ],
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
                          Expanded(
                            child: Text(
                              '$category • $city',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.mutedSilver,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
              const SizedBox(height: 10),
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

            // Specialization tags
            if (specializations.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: specializations.map((spec) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.darkSurfaceVariant,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.borderDark),
                    ),
                    child: Text(
                      spec,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.warmIvory,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],

            // Service Locations
            if (serviceLocations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.map, size: 12, color: AppColors.mutedSilver),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Serves: ${serviceLocations.join(', ')}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedSilver,
                        fontStyle: FontStyle.italic,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            // Availability Note Banner
            if (availabilityNote != null && availabilityNote.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.statusAccepted.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.statusAccepted.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.event_available,
                      size: 14,
                      color: AppColors.statusAccepted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Availability: $availabilityNote',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.warmIvory,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
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
