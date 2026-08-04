// lib/core/services/geofence_service.dart
//
// Owns per-company geofence settings and the pure distance check.
// Uses the `geolocator` package's distanceBetween (Haversine
// formula, meters) — no external API needed.

import 'package:geolocator/geolocator.dart';

import 'supabase_service.dart';
import '../../shared/models/geofence_settings_model.dart';

class GeofenceService {
  static final _db = SupabaseService.client;

  static Future<GeofenceSettings> getSettings(String companyId) async {
    final res = await _db
        .from('companies')
        .select(
          'geofence_enabled, geofence_latitude, geofence_longitude, geofence_radius_meters',
        )
        .eq('id', companyId)
        .single();

    return GeofenceSettings.fromMap(res);
  }

  /// Manager-only in practice, enforced by the existing
  /// `companies_update` RLS policy (is_company_manager).
  static Future<void> updateSettings({
    required String companyId,
    required GeofenceSettings settings,
  }) async {
    await _db.from('companies').update(settings.toMap()).eq('id', companyId);
  }

  /// True if [currentLat]/[currentLng] is within the configured
  /// radius. Always true if geofencing isn't enabled or no location
  /// has been set yet (fails open — a misconfigured geofence
  /// shouldn't lock everyone out of clocking in).
  static bool isWithinGeofence({
    required GeofenceSettings settings,
    required double currentLat,
    required double currentLng,
  }) {
    if (!settings.enabled || !settings.hasLocationSet) return true;

    final distance = Geolocator.distanceBetween(
      settings.latitude!,
      settings.longitude!,
      currentLat,
      currentLng,
    );

    return distance <= settings.radiusMeters;
  }
}