import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyp_app/services/portfolio_service.dart';
import 'package:pyp_app/widgets/portfolio_manager_widget.dart';
import 'package:pyp_app/widgets/portfolio_viewer_widget.dart';
import 'package:pyp_app/widgets/image_preview_dialog.dart';

void main() {
  Uint8List makeJpegBytes([int length = 100]) {
    final b = Uint8List(length);
    b[0] = 0xFF;
    b[1] = 0xD8;
    b[2] = 0xFF;
    b[3] = 0xE0;
    return b;
  }

  Uint8List makePngBytes([int length = 100]) {
    final b = Uint8List(length);
    b[0] = 0x89;
    b[1] = 0x50;
    b[2] = 0x4E;
    b[3] = 0x47;
    return b;
  }

  Uint8List makeWebpBytes([int length = 100]) {
    final b = Uint8List(length);
    b[0] = 0x52;
    b[1] = 0x49;
    b[2] = 0x46;
    b[3] = 0x46;
    b[8] = 0x57;
    b[9] = 0x45;
    b[10] = 0x42;
    b[11] = 0x50;
    return b;
  }

  group('PortfolioService Unit Tests', () {
    test('Image validation accepts valid JPEG, PNG, and WebP under 10MB', () {
      final jpegBytes = makeJpegBytes(1024 * 1024);
      final pngBytes = makePngBytes(1024 * 1024);
      final webpBytes = makeWebpBytes(1024 * 1024);

      expect(
        () => PortfolioService.validateImage(
          bytes: jpegBytes,
          fileName: 'sample.jpg',
        ),
        returnsNormally,
      );
      expect(
        () => PortfolioService.validateImage(
          bytes: jpegBytes,
          fileName: 'sample.jpeg',
        ),
        returnsNormally,
      );
      expect(
        () => PortfolioService.validateImage(
          bytes: pngBytes,
          fileName: 'sample.png',
        ),
        returnsNormally,
      );
      expect(
        () => PortfolioService.validateImage(
          bytes: webpBytes,
          fileName: 'sample.webp',
        ),
        returnsNormally,
      );
    });

    test(
      'Image validation rejects spoofed files missing valid header magic bytes',
      () {
        final invalidBytes = Uint8List(100); // filled with 0s
        expect(
          () => PortfolioService.validateImage(
            bytes: invalidBytes,
            fileName: 'fake.jpg',
          ),
          throwsA(
            isA<PortfolioValidationException>().having(
              (e) => e.message,
              'message',
              contains('Invalid image content'),
            ),
          ),
        );
      },
    );

    test('Image validation rejects disallowed extensions', () {
      final bytes = Uint8List(512);
      expect(
        () => PortfolioService.validateImage(
          bytes: bytes,
          fileName: 'document.pdf',
        ),
        throwsA(
          isA<PortfolioValidationException>().having(
            (e) => e.message,
            'message',
            contains('Invalid file type'),
          ),
        ),
      );
      expect(
        () => PortfolioService.validateImage(
          bytes: bytes,
          fileName: 'script.exe',
        ),
        throwsA(isA<PortfolioValidationException>()),
      );
    });

    test('Image validation rejects files exceeding 10MB', () {
      final oversizedBytes = Uint8List(11 * 1024 * 1024); // 11MB
      expect(
        () => PortfolioService.validateImage(
          bytes: oversizedBytes,
          fileName: 'large.jpg',
        ),
        throwsA(
          isA<PortfolioValidationException>().having(
            (e) => e.message,
            'message',
            contains('exceeds maximum allowed limit of 10MB'),
          ),
        ),
      );
    });

    test('Image validation rejects empty files', () {
      final emptyBytes = Uint8List(0);
      expect(
        () => PortfolioService.validateImage(
          bytes: emptyBytes,
          fileName: 'empty.jpg',
        ),
        throwsA(
          isA<PortfolioValidationException>().having(
            (e) => e.message,
            'message',
            contains('Selected file is empty'),
          ),
        ),
      );
    });

    test('Sanitizes filenames safely', () {
      expect(
        PortfolioService.sanitizeFileName('my photo #1.png'),
        'my_photo__1.png',
      );
      expect(
        PortfolioService.sanitizeFileName('special!@#\$%^&*().jpg'),
        'special__________.jpg',
      );
      expect(
        PortfolioService.sanitizeFileName('normal_file.webp'),
        'normal_file.webp',
      );
    });

    test('Generates object paths enforcing user_id folder prefix', () {
      const userId = 'usr_12345';
      const fileName = 'wedding photo.jpg';
      final path = PortfolioService.generateObjectPath(userId, fileName);

      expect(path.startsWith('usr_12345/'), isTrue);
      expect(path.endsWith('_wedding_photo.jpg'), isTrue);
    });

    test('Extracts storage path from full Supabase Storage URL', () {
      const fullUrl =
          'http://127.0.0.1:54321/storage/v1/object/public/portfolio_images/usr_12345/160000_sample.jpg';
      final path = PortfolioService.extractStoragePath(fullUrl);
      expect(path, 'usr_12345/160000_sample.jpg');

      const relativePath = 'usr_12345/160000_sample.jpg';
      expect(PortfolioService.extractStoragePath(relativePath), relativePath);
    });

    test('Resolves MIME types accurately', () {
      expect(PortfolioService.getMimeType('photo.jpg'), 'image/jpeg');
      expect(PortfolioService.getMimeType('photo.jpeg'), 'image/jpeg');
      expect(PortfolioService.getMimeType('graphic.png'), 'image/png');
      expect(PortfolioService.getMimeType('banner.webp'), 'image/webp');
      expect(PortfolioService.getMimeType('unknown.xyz'), 'image/jpeg');
    });
  });

  group('Portfolio Widgets Tests', () {
    testWidgets(
      'PortfolioViewerWidget renders empty message when URLs list is empty',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PortfolioViewerWidget(
                portfolioUrls: [],
                photographerName: 'John Photographer',
              ),
            ),
          ),
        );

        expect(find.text('No portfolio work published yet'), findsOneWidget);
        expect(find.byIcon(Icons.photo_library_outlined), findsOneWidget);
      },
    );

    testWidgets(
      'PortfolioViewerWidget renders thumbnail items when URLs are present',
      (WidgetTester tester) async {
        const sampleUrls = [
          'http://127.0.0.1:54321/storage/v1/object/public/portfolio_images/u1/1.jpg',
          'http://127.0.0.1:54321/storage/v1/object/public/portfolio_images/u1/2.jpg',
        ];

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PortfolioViewerWidget(
                portfolioUrls: sampleUrls,
                photographerName: 'Jane Studio',
              ),
            ),
          ),
        );

        expect(find.text('PORTFOLIO WORK (2)'), findsOneWidget);
        expect(find.byType(ListView), findsOneWidget);
      },
    );

    testWidgets(
      'PortfolioManagerWidget renders empty portfolio placeholder card',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PortfolioManagerWidget(initialPortfolioUrls: []),
            ),
          ),
        );

        expect(find.text('Portfolio Showcase (0)'), findsOneWidget);
        expect(find.text('No Portfolio Photos Uploaded Yet'), findsOneWidget);
        expect(
          find.byKey(const Key('empty_portfolio_upload_button')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'PortfolioManagerWidget renders image grid when portfolio items exist',
      (WidgetTester tester) async {
        const sampleUrls = [
          'http://127.0.0.1:54321/storage/v1/object/public/portfolio_images/u1/p1.jpg',
        ];

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PortfolioManagerWidget(initialPortfolioUrls: sampleUrls),
            ),
          ),
        );

        expect(find.text('Portfolio Showcase (1)'), findsOneWidget);
        expect(find.byType(GridView), findsOneWidget);
        expect(find.byKey(const Key('replace_photo_button_0')), findsOneWidget);
        expect(find.byKey(const Key('delete_photo_button_0')), findsOneWidget);
      },
    );

    testWidgets('ImagePreviewDialog renders title and close button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ImagePreviewDialog(
            imageUrl:
                'http://127.0.0.1:54321/storage/v1/object/public/portfolio_images/u1/p1.jpg',
            title: 'Sample Preview',
          ),
        ),
      );

      expect(find.text('Sample Preview'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });
}
