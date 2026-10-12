import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'image_preview_dialog.dart';

/// Editorial Widget to display a published photographer's portfolio to customers.
class PortfolioViewerWidget extends StatelessWidget {
  final List<String> portfolioUrls;
  final String photographerName;

  const PortfolioViewerWidget({
    super.key,
    required this.portfolioUrls,
    required this.photographerName,
  });

  @override
  Widget build(BuildContext context) {
    if (portfolioUrls.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderDark),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              color: AppColors.mutedSilver,
              size: 18,
            ),
            SizedBox(width: 8),
            Text(
              'No portfolio work published yet',
              style: TextStyle(
                color: AppColors.mutedSilver,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.collections,
              size: 18,
              color: AppColors.champagneGold,
            ),
            const SizedBox(width: 6),
            Text(
              'PORTFOLIO WORK (${portfolioUrls.length})',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: AppColors.champagneGold,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: portfolioUrls.length,
            itemBuilder: (context, index) {
              final url = portfolioUrls[index];
              return Padding(
                padding: const EdgeInsets.only(right: 10.0),
                child: GestureDetector(
                  onTap: () => ImagePreviewDialog.show(
                    context,
                    imageUrl: url,
                    title:
                        '$photographerName (${index + 1}/${portfolioUrls.length})',
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10.0),
                    child: Container(
                      width: 120,
                      height: 120,
                      color: AppColors.darkSurfaceVariant,
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.champagneGold,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image,
                                color: AppColors.mutedSilver,
                                size: 28,
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Image error',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.mutedSilver,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
