import 'package:flutter/material.dart';
import 'image_preview_dialog.dart';

/// Widget to display a published photographer's portfolio to customers.
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
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, color: Colors.grey),
            SizedBox(width: 8),
            Text(
              'No portfolio images available',
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
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
            const Icon(Icons.collections, size: 20, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Text(
              'Portfolio (${portfolioUrls.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                padding: const EdgeInsets.only(right: 8.0),
                child: GestureDetector(
                  onTap: () => ImagePreviewDialog.show(
                    context,
                    imageUrl: url,
                    title: '$photographerName Portfolio (${index + 1}/${portfolioUrls.length})',
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Container(
                      width: 120,
                      height: 120,
                      color: Colors.grey.shade300,
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, color: Colors.grey),
                              SizedBox(height: 4),
                              Text('Error', style: TextStyle(fontSize: 10, color: Colors.grey)),
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
