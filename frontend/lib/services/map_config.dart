/// Tile provider configuration for the SafeSphere map (flutter_map).
///
/// Free by default: OpenStreetMap raster tiles — no account, no API key, no
/// card. If prettier vector-style tiles are wanted later, pass a free MapTiler
/// key (100k loads/month) at build time:
///   flutter build apk --release --dart-define=SAFESPHERE_MAP_TILER_KEY=<key>
/// The same map code then switches providers automatically.
class SafeSphereMapConfig {
  /// Fallback map center (old Delhi default) used only before a real GPS fix —
  /// the UI never presents it as the user's location.
  static const double defaultLatitude = 28.6139;
  static const double defaultLongitude = 77.2090;

  static const String _mapTilerKey =
      String.fromEnvironment('SAFESPHERE_MAP_TILER_KEY');

  /// True when a MapTiler key was provided at build time.
  static bool get isMapTilerConfigured => _mapTilerKey.isNotEmpty;

  /// Raster tile URL template consumed by flutter_map's TileLayer.
  /// Default: CARTO dark basemap (fits the app's dark theme; free with
  /// attribution, OSM data). Switch the string to
  /// 'https://tile.openstreetmap.org/{z}/{x}/{y}.png' for classic OSM tiles.
  static String get tileUrlTemplate => isMapTilerConfigured
      ? 'https://api.maptiler.com/maps/basic-v2/{z}/{x}/{y}.png?key=$_mapTilerKey'
      : 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';

  /// Attribution text shown on the map (required by tile usage policies).
  static String get attribution => isMapTilerConfigured
      ? '© MapTiler © OpenStreetMap contributors'
      : '© OpenStreetMap contributors © CARTO';

  static const String attributionUrl = 'https://www.openstreetmap.org/copyright';

  /// Package name sent as User-Agent with tile requests (OSM policy compliance).
  static const String userAgentPackageName = 'com.safesphere.app';
}