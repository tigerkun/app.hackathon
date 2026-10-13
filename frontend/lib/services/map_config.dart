/// Google Maps Configuration & Map Theming for SafeSphere
class SafeSphereMapConfig {
  /// Default center coordinates (fallback when GPS is disabled)
  static const double defaultLatitude = 28.6139;
  static const double defaultLongitude = 77.2090;

  /// Configured Google Maps API Key
  /// Replace with your active Google Cloud Console Maps API Key
  static const String apiKey = "YOUR_GOOGLE_MAPS_API_KEY_HERE";

  /// Returns true if a genuine API key has been configured
  static bool get isConfigured =>
      apiKey.isNotEmpty && apiKey != "YOUR_GOOGLE_MAPS_API_KEY_HERE";

  /// Custom Dark Cyberpunk Map Style JSON for Google Maps
  static const String darkMapStyle = '''
[
  {
    "elementType": "geometry",
    "stylers": [{"color": "#0B1220"}]
  },
  {
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#8E9BB0"}]
  },
  {
    "elementType": "labels.text.stroke",
    "stylers": [{"color": "#0B1220"}]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#2FE0C9"}]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#6B7280"}]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [{"color": "#111C30"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry",
    "stylers": [{"color": "#1E293B"}]
  },
  {
    "featureType": "road",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#0F172A"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry",
    "stylers": [{"color": "#3A7BFF"}]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [{"color": "#1E40AF"}]
  },
  {
    "featureType": "transit",
    "elementType": "geometry",
    "stylers": [{"color": "#182234"}]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [{"color": "#060A12"}]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [{"color": "#38BDF8"}]
  }
]
''';
}
