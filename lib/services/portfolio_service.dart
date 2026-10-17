import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Exception thrown when portfolio image validation fails.
class PortfolioValidationException implements Exception {
  final String message;
  const PortfolioValidationException(this.message);

  @override
  String toString() => message;
}

/// Service handling portfolio image validation, upload, deletion, and schema updates.
class PortfolioService {
  static const String bucketName = 'portfolio_images';
  static const int maxFileSizeBytes = 10 * 1024 * 1024; // 10MB
  static const List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  static const Map<String, String> mimeTypeMap = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  /// Sanitizes file names to remove special characters.
  static String sanitizeFileName(String fileName) {
    final clean = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return clean.isEmpty ? 'portfolio_image.jpg' : clean;
  }

  /// Extracts file extension from a filename.
  static String getExtension(String fileName) {
    final parts = fileName.split('.');
    if (parts.length < 2) return '';
    return parts.last.toLowerCase();
  }

  /// Resolves MIME type for a given filename or extension.
  static String getMimeType(String fileName) {
    final ext = getExtension(fileName);
    return mimeTypeMap[ext] ?? 'image/jpeg';
  }

  /// Checks whether raw bytes match valid magic byte signatures for JPEG, PNG, or WebP.
  static bool hasValidMagicBytes(Uint8List bytes) {
    if (bytes.length < 12) return false;

    // JPEG: FF D8 FF
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

    // PNG: 89 50 4E 47 (\x89PNG)
    final isPng =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;

    // WebP: RIFF (bytes 0..3) ... WEBP (bytes 8..11)
    final isWebP =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;

    return isJpeg || isPng || isWebP;
  }

  /// Validates image bytes, file name, extension, file size, and magic bytes.
  /// Throws [PortfolioValidationException] if validation fails.
  static void validateImage({
    required Uint8List bytes,
    required String fileName,
  }) {
    if (bytes.isEmpty) {
      throw const PortfolioValidationException('Selected file is empty.');
    }

    final ext = getExtension(fileName);
    if (!allowedExtensions.contains(ext)) {
      throw PortfolioValidationException(
        'Invalid file type ".$ext". Allowed formats: ${allowedExtensions.map((e) => ".$e").join(', ')}.',
      );
    }

    if (bytes.length > maxFileSizeBytes) {
      final sizeMB = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
      throw PortfolioValidationException(
        'File size ($sizeMB MB) exceeds maximum allowed limit of 10MB.',
      );
    }

    if (!hasValidMagicBytes(bytes)) {
      throw const PortfolioValidationException(
        'Invalid image content. File header signature does not match JPEG, PNG, or WebP image formats.',
      );
    }
  }

  /// Generates a safe storage object path formatted as `<userId>/<timestamp>_<sanitizedFileName>`.
  static String generateObjectPath(String userId, String fileName) {
    final sanitized = sanitizeFileName(fileName);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$userId/${timestamp}_$sanitized';
  }

  /// Extracts the relative storage path from a full public Supabase Storage URL or relative path.
  static String extractStoragePath(String url) {
    if (url.contains('/$bucketName/')) {
      final parts = url.split('/$bucketName/');
      return parts.last;
    }
    return url;
  }

  /// Uploads an image binary to the user's folder in the `portfolio_images` bucket.
  /// Enforces server-side ownership by putting [userId] as top-level folder in storage path.
  Future<String> uploadPortfolioImage({
    required SupabaseClient client,
    required Uint8List bytes,
    required String fileName,
    String? userId,
  }) async {
    final currentUserId = userId ?? client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw const PortfolioValidationException('User is not authenticated.');
    }

    // 1. Validate image format & size
    validateImage(bytes: bytes, fileName: fileName);

    // 2. Generate path enforcing ownership ($userId/...)
    final objectPath = generateObjectPath(currentUserId, fileName);
    final mimeType = getMimeType(fileName);

    // 3. Upload to Supabase Storage
    await client.storage
        .from(bucketName)
        .uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );

    // 4. Get and return public URL
    final publicUrl = client.storage.from(bucketName).getPublicUrl(objectPath);
    return publicUrl;
  }

  /// Deletes an image object from Supabase Storage by its public URL or object path.
  Future<void> deletePortfolioImage({
    required SupabaseClient client,
    required String url,
    String? userId,
  }) async {
    final currentUserId = userId ?? client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw const PortfolioValidationException('User is not authenticated.');
    }

    final objectPath = extractStoragePath(url);
    if (objectPath.isEmpty) return;

    // Safety check: ensure objectPath belongs to the user's folder
    if (!objectPath.startsWith('$currentUserId/')) {
      throw const PortfolioValidationException(
        'Unauthorized: Cannot delete files outside your own portfolio folder.',
      );
    }

    await client.storage.from(bucketName).remove([objectPath]);
  }

  /// Updates the `portfolio_urls` array on `photographer_profiles` table for current user.
  Future<List<String>> savePortfolioUrls({
    required SupabaseClient client,
    required List<String> portfolioUrls,
    String? userId,
  }) async {
    final currentUserId = userId ?? client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw const PortfolioValidationException('User is not authenticated.');
    }

    // Deduplicate URLs while retaining order
    final cleanUrls = portfolioUrls.toSet().toList();

    await client
        .from('photographer_profiles')
        .update({'portfolio_urls': cleanUrls})
        .eq('user_id', currentUserId);

    return cleanUrls;
  }
}
