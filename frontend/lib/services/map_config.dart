/// Tile provider configuration for the SafeSphere map (flutter_map).
///
/// Free by default: OpenStreetMap standard raster tiles with flutter_map's
/// built-in darkModeTileBuilder for dark-mode rendering — no account, no
/// API key, no card.
/// If prettier vector-style tiles are wanted later, pass a free MapTiler
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
  /// Default: standard OpenStreetMap tiles (free, no key). flutter_map's
  /// built-in darkModeTileBuilder is used to invert tiles into dark mode.
  /// NOTE: CARTO dark_all tiles now require an API key and are no longer
  /// used as the free default.
  static String get tileUrlTemplate => isMapTilerConfigured
      ? 'https://api.maptiler.com/maps/basic-v2/{z}/{x}/{y}.png?key=$_mapTilerKey'
      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// True when tiles are natively dark-themed (MapTiler, etc).
  /// When false, the map widget must apply darkModeTileBuilder.
  static bool get needsDarkFilter => !isMapTilerConfigured;

  /// Attribution text shown on the map (required by tile usage policies).
  static String get attribution => isMapTilerConfigured
      ? '© MapTiler © OpenStreetMap contributors'
      : '© OpenStreetMap contributors';

  static const String attributionUrl = 'https://www.openstreetmap.org/copyright';

  /// Package name sent as User-Agent with tile requests (OSM policy compliance).
  static const String userAgentPackageName = 'com.safesphere.app';
}
