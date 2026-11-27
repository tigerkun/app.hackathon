import 'package:flutter/material.dart';
import '../data/auth_state.dart';
import 'app_routes.dart';
import '../pages/home_page.dart';
import '../pages/safety_map_page.dart';
import '../pages/report_page.dart';
import '../pages/community_alerts_page.dart';
import '../pages/ai_assistant_page.dart';
import '../pages/share_location_page.dart';
import '../pages/track_session_page.dart';
import '../pages/emergency_page.dart';
import '../pages/about_page.dart';
import '../pages/auth/login_page.dart';
import '../pages/auth/register_page.dart';
import '../pages/auth/phone_otp_page.dart';
import '../pages/auth/pin_lock_page.dart';
import '../pages/onboarding_page.dart';
import '../pages/review_markers_page.dart';
import '../pages/my_circle_page.dart';
import '../pages/privacy_hub_page.dart';

class RouteGuard {
  static Route<dynamic> _buildAnimatedRoute(WidgetBuilder builder, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final disable = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (disable) return child;
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.03, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static Route<dynamic> generateRoute(RouteSettings settings, AuthState authState) {
    final String routeName = settings.name ?? AppRoutes.home;

    // 1. Invariant Emergency Bypass (routes /emergency and /share NEVER blocked)
    if (routeName == AppRoutes.emergency || routeName == AppRoutes.shareLocation) {
      return _buildAnimatedRoute(
        (_) => _resolveEmergencyPage(routeName),
        settings,
      );
    }

    // 2. PIN Lock Barrier (redirects to /pin-lock if isPinLocked)
    if (authState.isPinLocked && routeName != AppRoutes.login) {
      return _buildAnimatedRoute(
        (_) => const PinLockPage(),
        settings,
      );
    }

    // 3. Auth Routes
    if (routeName == AppRoutes.login) {
      return _buildAnimatedRoute((_) => const LoginPage(), settings);
    }
    if (routeName == AppRoutes.register) {
      return _buildAnimatedRoute((_) => const RegisterPage(), settings);
    }
    if (routeName == AppRoutes.otp) {
      final phone = settings.arguments is String ? settings.arguments as String : authState.pendingPhone;
      return _buildAnimatedRoute((_) => PhoneOtpPage(phone: phone), settings);
    }
    if (routeName == AppRoutes.pinLock) {
      return _buildAnimatedRoute((_) => const PinLockPage(), settings);
    }
    if (routeName == AppRoutes.onboarding) {
      return _buildAnimatedRoute((_) => const OnboardingPage(), settings);
    }

    // 4. Protected Routes (/profile, /contacts, /circle, /privacy-hub)
    if (routeName == AppRoutes.profile ||
        routeName == AppRoutes.contacts ||
        routeName == AppRoutes.circle ||
        routeName == AppRoutes.privacyHub) {
      if (!authState.isAuthenticated) {
        return _buildAnimatedRoute((_) => LoginPage(redirectRoute: routeName), settings);
      }
      if (routeName == AppRoutes.circle) {
        return _buildAnimatedRoute((_) => const MyCirclePage(), settings);
      }
      if (routeName == AppRoutes.privacyHub) {
        return _buildAnimatedRoute((_) => const PrivacyHubPage(), settings);
      }
    }

    // Review Markers (Admin / Responder only)
    if (routeName == AppRoutes.reviewMarkers) {
      if (!authState.isAuthenticated || !authState.isPrivileged) {
        return _buildAnimatedRoute((_) => const HomePage(), settings);
      }
      return _buildAnimatedRoute((_) => const ReviewMarkersPage(), settings);
    }

    // 5. Protected Route (/report)
    if (routeName == AppRoutes.report) {
      // Allowed for authenticated and guests with emergency reporting
      return _buildAnimatedRoute((_) => const ReportPage(), settings);
    }

    // 6. Guest Fallback & Standard Route Resolution
    // (allows guest browsing of /home, /safety-map, /alerts, /ai-assistant, /about)
    return _buildAnimatedRoute(
      (_) => _resolveStandardPage(routeName, isOnboarded: authState.isOnboarded),
      settings,
    );
  }

  static Widget _resolveEmergencyPage(String routeName) {
    if (routeName == AppRoutes.shareLocation) {
      return const ShareLocationPage();
    }
    return const EmergencyPage();
  }

  static Widget _resolveStandardPage(String routeName, {bool isOnboarded = true}) {
    if (!isOnboarded && routeName != AppRoutes.about) {
      return const OnboardingPage();
    }
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
      case AppRoutes.trackSession:
        return const TrackSessionPage();
      case AppRoutes.about:
        return const AboutPage();
      case AppRoutes.reviewMarkers:
        return const ReviewMarkersPage();
      default:
        return const HomePage();
    }
  }
}
