# SafeSphere Mobile App (Flutter)

The SafeSphere mobile application provides personal safety, emergency SOS, interactive geospatial mapping, and incident reporting.

## Key Subsystems
- **Authentication**: `lib/services/auth_service.dart`, `lib/models/user_model.dart`, `lib/pages/login_page.dart`, `lib/pages/signup_page.dart`, `lib/pages/auth_pin_page.dart`
- **Emergency Hardware**: `lib/pages/emergency_page.dart` (Telephony dialer to 112, 181, 108, 101)
- **Geospatial & Safe Route**: `lib/pages/safety_map_page.dart`, `lib/pages/share_location_page.dart`
- **Incident Crowdsourcing**: `lib/pages/report_page.dart`, `lib/data/report_store.dart`
- **AI Safety Assistant**: `lib/pages/ai_assistant_page.dart`
- **Community Safety Alerts**: `lib/pages/community_alerts_page.dart`

## Execution
```bash
# Run on connected device or simulator
flutter run

# Execute test suite
flutter test
```
