import 'package:flutter_test/flutter_test.dart';
import 'package:knight_shift/core/services/geofence_service.dart';
import 'package:knight_shift/shared/models/geofence_settings_model.dart';

void main() {
  group('GeofenceService.isWithinGeofence', () {
    test('disabled geofence always allows', () {
      final settings = GeofenceSettings(enabled: false, radiusMeters: 150);
      expect(GeofenceService.isWithinGeofence(
        settings: settings,
        currentLat: 0.0,
        currentLng: 0.0,
      ), isTrue);
    });

    test('no location set always allows', () {
      final settings = GeofenceSettings(enabled: true, radiusMeters: 150);
      expect(GeofenceService.isWithinGeofence(
        settings: settings,
        currentLat: 0.0,
        currentLng: 0.0,
      ), isTrue);
    });

    test('user within radius is allowed', () {
      final settings = GeofenceSettings(
        enabled: true,
        latitude: 37.7749,
        longitude: -122.4194,
        radiusMeters: 1000,
      );
      // Same location — distance is 0
      expect(GeofenceService.isWithinGeofence(
        settings: settings,
        currentLat: 37.7749,
        currentLng: -122.4194,
      ), isTrue);
    });

    test('user outside radius is denied', () {
      final settings = GeofenceSettings(
        enabled: true,
        latitude: 37.7749,
        longitude: -122.4194,
        radiusMeters: 100,
      );
      // ~1.5km away
      expect(GeofenceService.isWithinGeofence(
        settings: settings,
        currentLat: 37.7900,
        currentLng: -122.4194,
      ), isFalse);
    });

    test('user well inside smaller radius is allowed', () {
      final settings = GeofenceSettings(
        enabled: true,
        latitude: 37.7749,
        longitude: -122.4194,
        radiusMeters: 100,
      );
      // Very close — definitely within 100m
      expect(GeofenceService.isWithinGeofence(
        settings: settings,
        currentLat: 37.7750,
        currentLng: -122.4194,
      ), isTrue);
    });
  });
}
