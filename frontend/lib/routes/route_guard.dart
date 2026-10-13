import 'package:flutter/material.dart';
import '../data/auth_state.dart';
import 'app_routes.dart';
import '../pages/home_page.dart';
import '../pages/safety_map_page.dart';
import '../pages/report_page.dart';
import '../pages/community_alerts_page.dart';
import '../pages/ai_assistant_page.dart';
import '../pages/share_location_page.dart';
import '../pages/emergency_page.dart';
import '../pages/about_page.dart';
import '../pages/auth/login_page.dart';
import '../pages/auth/register_page.dart';
import '../pages/auth/phone_otp_page.dart';
import '../pages/auth/pin_lock_page.dart';

class RouteGuard {
  static Route<dynamic> generateRoute(RouteSettings settings, AuthState authState) {
    final String routeName = settings.name ?? AppRoutes.home;

    // 1. Invariant Emergency Bypass (routes /emergency and /share NEVER blocked)
    if (routeName == AppRoutes.emergency || routeName == AppRoutes.shareLocation) {
      return MaterialPageRoute(
        builder: (_) => _resolveEmergencyPage(routeName),
        settings: settings,
      );
    }

    // 2. PIN Lock Barrier (redirects to /pin-lock if isPinLocked)
    if (authState.isPinLocked && routeName != AppRoutes.login) {
      return MaterialPageRoute(
        builder: (_) => const PinLockPage(),
        settings: settings,
      );
    }

    // 3. Auth Routes
    if (routeName == AppRoutes.login) {
      return MaterialPageRoute(
        builder: (_) => const LoginPage(),
        settings: settings,
      );
    }
    if (routeName == AppRoutes.register) {
      return MaterialPageRoute(
        builder: (_) => const RegisterPage(),
        settings: settings,
      );
    }
    if (routeName == AppRoutes.otp) {
      final phone = settings.arguments is String ? settings.arguments as String : authState.pendingPhone;
      return MaterialPageRoute(
        builder: (_) => PhoneOtpPage(phone: phone),
        settings: settings,
      );
    }
    if (routeName == AppRoutes.pinLock) {
      return MaterialPageRoute(
        builder: (_) => const PinLockPage(),
        settings: settings,
      );
    }

    // 4. Protected Routes (/profile, /contacts)
    if (routeName == AppRoutes.profile || routeName == AppRoutes.contacts) {
      if (!authState.isAuthenticated) {
        return MaterialPageRoute(
          builder: (_) => LoginPage(redirectRoute: routeName),
          settings: settings,
        );
      }
    }

    // 5. Protected Route (/report)
    if (routeName == AppRoutes.report) {
      // Allowed for authenticated and guests with emergency reporting
      return MaterialPageRoute(
        builder: (_) => const ReportPage(),
        settings: settings,
      );
    }

    // 6. Guest Fallback & Standard Route Resolution
    // (allows guest browsing of /home, /safety-map, /alerts, /ai-assistant, /about)
    return MaterialPageRoute(
      builder: (_) => _resolveStandardPage(routeName),
      settings: settings,
    );
  }

  static Widget _resolveEmergencyPage(String routeName) {
    if (routeName == AppRoutes.shareLocation) {
      return const ShareLocationPage();
    }
    return const EmergencyPage();
  }

  static Widget _resolveStandardPage(String routeName) {
    switch (routeName) {
      case AppRoutes.root:
      case AppRoutes.home:
        return const HomePage();
      case AppRoutes.safetyMap:
      case '/map':
        return const SafetyMapPage();
      case AppRoutes.report:
        return const ReportPage();
      case AppRoutes.alerts:
      case '/community':
        return const CommunityAlertsPage();
      case AppRoutes.aiAssistant:
      case '/chat':
        return const AiAssistantPage();
      case AppRoutes.about:
        return const AboutPage();
      default:
        return const HomePage();
    }
  }
}
