// lib/shared/models/geofence_settings_model.dart

class GeofenceSettings {
  final bool enabled;
  final double? latitude;
  final double? longitude;
  final double radiusMeters;

  const GeofenceSettings({
    required this.enabled,
    this.latitude,
    this.longitude,
    required this.radiusMeters,
  });

  static const defaults = GeofenceSettings(
    enabled: false,
    radiusMeters: 150,
  );

  bool get hasLocationSet => latitude != null && longitude != null;

  factory GeofenceSettings.fromMap(Map<String, dynamic> map) {
    return GeofenceSettings(
      enabled: map['geofence_enabled'] as bool? ?? false,
      latitude: map['geofence_latitude'] == null
          ? null
          : (map['geofence_latitude'] as num).toDouble(),
      longitude: map['geofence_longitude'] == null
          ? null
          : (map['geofence_longitude'] as num).toDouble(),
      radiusMeters: (map['geofence_radius_meters'] ?? 150).toDouble(),
    );
  }

  Map<String, dynamic> toMap() => {
        'geofence_enabled': enabled,
        'geofence_latitude': latitude,
        'geofence_longitude': longitude,
        'geofence_radius_meters': radiusMeters,
      };

  GeofenceSettings copyWith({
    bool? enabled,
    double? latitude,
    double? longitude,
    double? radiusMeters,
  }) {
    return GeofenceSettings(
      enabled: enabled ?? this.enabled,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
    );
  }
}