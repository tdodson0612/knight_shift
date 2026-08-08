// lib/core/services/clock_in_photo_service.dart
//
// Photo-on-clock-in: capture, upload to the private 'clock-in-photos'
// bucket, and short-lived signed URLs for viewing later. Photos are
// never public — every view goes through a signed URL that expires,
// not a permanent link.

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

import 'supabase_service.dart';

class ClockInPhotoService {
  static final _db = SupabaseService.client;
  static final _bucket = SupabaseService.client.storage.from('clock-in-photos');

  static Future<bool> isRequired(String companyId) async {
    final res = await _db
        .from('companies')
        .select('clock_in_photo_enabled')
        .eq('id', companyId)
        .single();
    return res['clock_in_photo_enabled'] as bool? ?? false;
  }

  /// Manager-only in practice via companies_update RLS.
  static Future<void> setRequired(String companyId, bool enabled) async {
    await _db
        .from('companies')
        .update({'clock_in_photo_enabled': enabled})
        .eq('id', companyId);
  }

  /// Opens the front camera, uploads the photo to
  /// {companyId}/{userId}/{timestamp}.jpg, and returns the storage
  /// path to save on the time_entries row. Returns null if the
  /// person cancels the camera — the caller decides what that means
  /// (this service doesn't enforce "required," home_screen does).
  static Future<String?> captureAndUpload({
    required String companyId,
    required String userId,
  }) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 60,
    );

    if (photo == null) return null;

    final bytes = await photo.readAsBytes();
    final path =
        '$companyId/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

    await _bucket.uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg'),
    );

    return path;
  }

  /// 10-minute signed URL — long enough to view, short enough that a
  /// leaked link isn't a standing liability.
  static Future<String> getSignedUrl(String path) async {
    return await _bucket.createSignedUrl(path, 60 * 10);
  }
}