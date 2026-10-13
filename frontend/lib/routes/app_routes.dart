class AppRoutes {
  static const String _p = '/';

  // Public & Authentication Routes
  static const String login = '${_p}login';
  static const String register = '${_p}register';
  static const String otp = '${_p}otp';
  static const String pinLock = '${_p}pin-lock';

  // Unconditional Emergency Routes (Zero Barrier)
  static const String emergency = '/emergency';
  static const String shareLocation = '/share';

  // Core App Routes (Guest & Authenticated)
  static const String home = '/home';
  static const String root = '/';
  static const String safetyMap = '/safety-map';
  static const String alerts = '/alerts';
  static const String aiAssistant = '/ai-assistant';
  static const String about = '/about';

  // Protected Routes (Full Authentication Required)
  static const String report = '/report';
  static const String profile = '${_p}profile';
  static const String contacts = '${_p}contacts';
}
