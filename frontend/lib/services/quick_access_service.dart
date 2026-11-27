import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// Bridges native Android quick-access triggers (Home Screen / Keyguard Widget,
/// Lock-Screen Quick Settings Tile, and App Icon Long-Press Shortcut) with Flutter.
class QuickAccessService {
  QuickAccessService._();

  static final QuickAccessService instance = QuickAccessService._();
  static const MethodChannel _channel = MethodChannel('com.safesphere/quick_access');

  /// Consumes a cold-start quick route (e.g. '/emergency') launched from widget/tile/shortcut.
  Future<String?> consumeInitialRoute() async {
    try {
      final route = await _channel.invokeMethod<String>('consumeInitialQuickRoute');
      if (route != null && route.isNotEmpty) {
        return route;
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Registers a callback for quick-access routes received while the app is running.
  void registerRouteHandler(void Function(String route) onRoute) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onQuickRoute' && call.arguments is String) {
        final route = call.arguments as String;
        if (route.isNotEmpty) {
          onRoute(route);
        }
      }
    });
  }

  Future<bool> isPinWidgetSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isPinWidgetSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> requestPinHomeWidget() async {
    try {
      return await _channel.invokeMethod<bool>('requestPinWidget') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isQuickTilePinSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isQuickTilePinSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String> requestAddLockQuickTile() async {
    try {
      return await _channel.invokeMethod<String>('requestAddQuickTile') ?? 'unsupported';
    } on MissingPluginException {
      return 'unsupported';
    } on PlatformException {
      return 'unsupported';
    }
  }

  /// Presents a setup sheet allowing users to pin the SOS Home Widget or Lock Quick Tile.
  static Future<void> showQuickAccessSetupSheet(BuildContext context) async {
    final pinSupported = await instance.isPinWidgetSupported();
    final tileSupported = await instance.isQuickTilePinSupported();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: AppColors.border),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: const [
                      CircleAvatar(
                        backgroundColor: Color(0x2EFF4C4C),
                        child: Icon(Icons.emergency_outlined, color: AppColors.red),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '1-Tap Emergency Access',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Keep SafeSphere SOS ready outside the app — opens Emergency SOS directly without login or PIN delays.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _QuickOptionCard(
                    icon: Icons.widgets_outlined,
                    accentColor: AppColors.red,
                    title: 'Home & Lock Screen SOS Widget',
                    description:
                        'Places a compact 1-tap EMERGENCY SOS + Dial 112 widget on your Home Screen (and Lock Screen on supported Android devices).',
                    buttonLabel: pinSupported ? 'Add SOS Widget to Home Screen' : 'How to Add Widget',
                    onPressed: () async {
                      final accepted = await instance.requestPinHomeWidget();
                      if (!context.mounted) return;
                      if (sheetCtx.mounted) {
                        Navigator.pop(sheetCtx);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            accepted
                                ? 'Confirm "Add" on the system prompt to place the SafeSphere SOS widget.'
                                : 'Long-press an empty space on your Home Screen -> Widgets -> SafeSphere -> drag "Emergency SOS".',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _QuickOptionCard(
                    icon: Icons.lock_clock_outlined,
                    accentColor: AppColors.teal,
                    title: 'Lock-Screen Quick Settings Tile',
                    description:
                        'Swipe down from the top of your Lock Screen and tap "SafeSphere SOS" to launch Emergency SOS immediately.',
                    buttonLabel: tileSupported ? 'Add Quick Settings Tile' : 'How to Enable Tile',
                    onPressed: () async {
                      final status = await instance.requestAddLockQuickTile();
                      if (!context.mounted) return;
                      if (sheetCtx.mounted) {
                        Navigator.pop(sheetCtx);
                      }
                      final String message;
                      switch (status) {
                        case 'added':
                          message = 'SafeSphere SOS added to your Quick Settings & Lock Screen shade.';
                          break;
                        case 'already_added':
                          message = 'SafeSphere SOS tile is already in your Quick Settings panel.';
                          break;
                        case 'declined':
                          message = 'Tile request dismissed. You can add it anytime from Quick Settings edit (pencil icon).';
                          break;
                        case 'requested':
                          message = 'Confirm the Quick Settings prompt to add SafeSphere SOS.';
                          break;
                        default:
                          message =
                              'Swipe down twice from your status bar -> tap Edit (pencil) -> drag "SafeSphere SOS" into active tiles.';
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(message),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.glass,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.touch_app_outlined, color: AppColors.amber, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Tip: You can also long-press the SafeSphere app icon anytime and tap "Emergency SOS" to jump straight to emergency help.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12.5,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuickOptionCard extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  const _QuickOptionCard({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: Text(buttonLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: accentColor == AppColors.red ? Colors.white : AppColors.bgDark,
                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
