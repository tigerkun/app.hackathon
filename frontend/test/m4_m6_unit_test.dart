import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

import '../lib/data/auth_state.dart';
import '../lib/pages/auth/phone_otp_page.dart';
import '../lib/pages/auth/register_page.dart';
import '../lib/pages/emergency_page.dart';
import '../lib/pages/home_page.dart';
import '../lib/services/auth_service.dart';
import '../lib/services/gesture_service.dart';
import '../lib/services/movement_analyzer.dart';
import '../lib/services/storage_service.dart';

class _PassthroughHttpOverrides extends HttpOverrides {}

class _InMemoryStorage implements IStorageService {
  final Map<String, String> data = {};

  @override
  Future<void> clear() async => data.clear();

  @override
  Future<String?> getString(String key) async => data[key];

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<void> setString(String key, String value) async {
    data[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M4 MovementAnalyzer', () {
    final now = DateTime.utc(2026, 11, 26, 12, 0, 0);

    test('returns unknown for empty or malformed inputs', () {
      expect(MovementAnalyzer.analyze([], now: now).state, 'unknown');
      expect(
        MovementAnalyzer.analyze([null, 'bad', {'latitude': 'nan', 'longitude': 77.0}], now: now).state,
        'unknown',
      );
      expect(
        MovementAnalyzer.analyze([{'latitude': 95.0, 'longitude': 77.0}], now: now).state,
        'unknown',
      );
    });

    test('single fresh fix is unknown; single stale >90s fix is stationary', () {
      final fresh = [
        {'latitude': 28.6315, 'longitude': 77.2167, 'timestamp': now.subtract(const Duration(seconds: 20)).toIso8601String()},
      ];
      expect(MovementAnalyzer.analyze(fresh, now: now).state, 'unknown');

      final older = [
        {'latitude': 28.6315, 'longitude': 77.2167, 'timestamp': now.subtract(const Duration(seconds: 100)).toIso8601String()},
      ];
      final res = MovementAnalyzer.analyze(older, now: now);
      expect(res.state, 'stationary');
      expect(res.summary, contains('stationary'));
    });

    test('detects stalled state when newest breadcrumb is >120s old', () {
      final fixes = [
        {'latitude': 28.6315, 'longitude': 77.2167, 'timestamp': now.subtract(const Duration(seconds: 200)).toIso8601String()},
        {'latitude': 28.6330, 'longitude': 77.2167, 'timestamp': now.subtract(const Duration(seconds: 135)).toIso8601String()},
      ];
      final res = MovementAnalyzer.analyze(fixes, now: now);
      expect(res.state, 'stalled');
      expect(res.secondsSinceLastUpdate, 135);
      expect(res.summary, contains('Signal lost'));
    });

    test('detects moving state with speed and compass heading', () {
      // ~111m per 0.001 deg lat north; 3 steps of 0.001 deg over 60s = ~333m / 60s = ~20 km/h north
      final fixes = [
        {'latitude': 28.6300, 'longitude': 77.2167, 'timestamp': now.subtract(const Duration(seconds: 65)).toIso8601String()},
        {'latitude': 28.6310, 'longitude': 77.2167, 'timestamp': now.subtract(const Duration(seconds: 45)).toIso8601String()},
        {'latitude': 28.6320, 'longitude': 77.2167, 'timestamp': now.subtract(const Duration(seconds: 25)).toIso8601String()},
        {'latitude': 28.6330, 'longitude': 77.2167, 'timestamp': now.subtract(const Duration(seconds: 5)).toIso8601String()},
      ];
      final res = MovementAnalyzer.analyze(fixes, now: now);
      expect(res.state, 'moving');
      expect(res.speedKmh, isNotNull);
      expect(res.speedKmh!, greaterThan(15.0));
      expect(res.headingLabel, 'north');
      expect(res.summary, contains('Moving at ~'));
    });

    test('detects stationary dwell after prior movement', () {
      final fixes = [
        {'latitude': 28.6300, 'longitude': 77.2167, 'timestamp': now.subtract(const Duration(minutes: 10)).toIso8601String()},
        {'latitude': 28.6315, 'longitude': 77.2167, 'timestamp': now.subtract(const Duration(minutes: 9)).toIso8601String()},
        {'latitude': 28.63151, 'longitude': 77.21671, 'timestamp': now.subtract(const Duration(minutes: 3)).toIso8601String()},
        {'latitude': 28.63152, 'longitude': 77.21672, 'timestamp': now.subtract(const Duration(seconds: 15)).toIso8601String()},
      ];
      // Total displacement inside trailing window has avg speed < 1.5 km/h over 9m45s? Wait: 0.0015 deg = ~167m / 585s = 1.03 km/h < 1.5 km/h!
      final res = MovementAnalyzer.analyze(fixes, now: now);
      expect(res.state, 'stationary');
      expect(res.summary, contains('Stationary for'));
    });
  });

  group('M6 Offline SOS Queue Idempotency', () {
    test('deduplicates identical SOS payloads even with different clientRequestId or 4dp jitter', () async {
      final storage = _InMemoryStorage();
      final auth = AuthService(baseUrl: 'http://127.0.0.1:1', storage: storage);

      await auth.queueOfflineSos({
        'latitude': 28.63150,
        'longitude': 77.21670,
        'alertType': 'sos',
        'clientRequestId': 'req-1',
      });
      await auth.queueOfflineSos({
        'latitude': 28.63151,
        'longitude': 77.21671,
        'alertType': 'sos',
        'clientRequestId': 'req-2',
      });

      final queued = await auth.getQueuedSosAlerts();
      expect(queued.length, 1);
      expect(queued.first['clientRequestId'], 'req-1');
    });

    test('keeps distinct SOS locations separate and serializes concurrent enqueues', () async {
      final storage = _InMemoryStorage();
      final auth = AuthService(baseUrl: 'http://127.0.0.1:1', storage: storage);

      await Future.wait([
        auth.queueOfflineSos({'latitude': 28.6315, 'longitude': 77.2167, 'alertType': 'sos'}),
        auth.queueOfflineSos({'latitude': 28.6315, 'longitude': 77.2167, 'alertType': 'sos'}),
        auth.queueOfflineSos({'latitude': 28.7000, 'longitude': 77.3000, 'alertType': 'sos'}),
      ]);

      final queued = await auth.getQueuedSosAlerts();
      expect(queued.length, 2);
    });

    test('prunes expired entries and enforces maxOfflineSosQueueSize cap', () async {
      final storage = _InMemoryStorage();
      final auth = AuthService(baseUrl: 'http://127.0.0.1:1', storage: storage);

      // Seed an expired entry (> 24h old)
      final staleTime = DateTime.now().toUtc().subtract(const Duration(hours: 25)).toIso8601String();
      await storage.setString(
        AuthService.keyOfflineSosQueue,
        jsonEncode([
          {'latitude': 10.0, 'longitude': 10.0, '_queuedAt': staleTime},
        ]),
      );

      for (int i = 0; i < AuthService.maxOfflineSosQueueSize + 3; i++) {
        await auth.queueOfflineSos({
          'latitude': 28.0 + i * 0.01,
          'longitude': 77.0,
          'alertType': 'sos',
        });
      }

      final queued = await auth.getQueuedSosAlerts();
      expect(queued.length, AuthService.maxOfflineSosQueueSize);
      // Oldest entries (including stale 10.0) were evicted/pruned; newest remain
      expect(queued.any((e) => e['latitude'] == 10.0), isFalse);
      expect(queued.last['latitude'], closeTo(28.0 + 22 * 0.01, 0.0001));
    });
  });

  group('M6 Per-Alert Resolve-Token Map', () {
    test('stores, resolves, and prunes multiple active SOS resolve tokens without clobbering siblings', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final resolvedTokensUsed = <String, String>{};
        int seq = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((HttpRequest req) async {
          final rawBody = await utf8.decoder.bind(req).join();
          final body = rawBody.isNotEmpty ? jsonDecode(rawBody) as Map<String, dynamic> : <String, dynamic>{};
          req.response.headers.contentType = ContentType.json;

          if (req.method == 'POST' && req.uri.path == '/api/v1/sos/trigger') {
            seq++;
            final id = 'sos_$seq';
            final tok = 'rtok_$seq';
            req.response.statusCode = 201;
            req.response.write(jsonEncode({
              'success': true,
              'data': {
                'id': id,
                'status': 'active',
                'resolveToken': tok,
              },
            }));
          } else if (req.method == 'POST' && req.uri.path.endsWith('/resolve')) {
            final id = req.uri.pathSegments[3];
            resolvedTokensUsed[id] = (body['resolveToken'] ?? '').toString();
            req.response.statusCode = 200;
            req.response.write(jsonEncode({
              'success': true,
              'data': {'id': id, 'status': 'resolved'},
            }));
          } else {
            req.response.statusCode = 404;
            req.response.write(jsonEncode({'success': false}));
          }
          await req.response.close();
        });

        final storage = _InMemoryStorage();
        final auth = AuthService(
          baseUrl: 'http://127.0.0.1:${server.port}',
          storage: storage,
        );

        final a1 = await auth.triggerSos(latitude: 28.63, longitude: 77.21);
        final a2 = await auth.triggerSos(latitude: 28.64, longitude: 77.22);
        expect(a1?['data']?['id'], 'sos_1');
        expect(a2?['data']?['id'], 'sos_2');

        expect(await auth.getSosResolveToken('sos_1'), 'rtok_1');
        expect(await auth.getSosResolveToken('sos_2'), 'rtok_2');

        // Resolving sos_1 uses rtok_1 and keeps sos_2's token intact
        expect(await auth.resolveSos(alertId: 'sos_1'), isTrue);
        expect(resolvedTokensUsed['sos_1'], 'rtok_1');
        expect(await auth.getSosResolveToken('sos_2'), 'rtok_2');

        // Resolving sos_2 uses rtok_2 and cleans up the legacy mirror key
        expect(await auth.resolveSos(alertId: 'sos_2'), isTrue);
        expect(resolvedTokensUsed['sos_2'], 'rtok_2');
        expect(await storage.getString(AuthService.keyActiveSosResolveToken), isNull);
      }, _PassthroughHttpOverrides());
    });

    test('falls back to legacy single-token key for pre-M6 alerts', () async {
      final storage = _InMemoryStorage();
      await storage.setString(AuthService.keyActiveSosResolveToken, 'legacy_tok');
      final auth = AuthService(baseUrl: 'http://127.0.0.1:1', storage: storage);

      expect(await auth.getSosResolveToken('sos_legacy'), 'legacy_tok');
    });
  });

  group('Hardening Regression Tests (PIN reset, Discreet Home, Gesture stack)', () {
    test('unlockPin after applyPinReset marks session unauthenticated instead of split-brain authenticated', () async {
      final storage = _InMemoryStorage();
      await storage.setString(AuthService.keyToken, 'tok_old');
      await storage.setString(AuthService.keyRefreshToken, 'rtok_old');
      await storage.setString(AuthService.keyUser, jsonEncode({
        'id': 'u1',
        'name': 'Test User',
        'email': 'u1@example.com',
        'phone': '9999999999',
      }));
      final auth = AuthService(baseUrl: 'http://127.0.0.1:1', storage: storage);
      await auth.setPin('1234');
      await auth.getProfile();

      final authState = AuthState(authService: auth);
      await authState.initialize();
      expect(authState.isPinLocked, isTrue);

      await auth.applyPinReset('5678');
      expect(await auth.verifyPin('1234'), isFalse);
      expect(await authState.unlockPin('5678'), isTrue);
      expect(authState.isAuthenticated, isFalse);
      expect(authState.status, AuthStatus.unauthenticated);
      expect(authState.currentUser, isNull);
    });

    testWidgets('HomePage mutes SOS hero and FAB visuals when Discreet Mode is active', (WidgetTester tester) async {
      final storage = _InMemoryStorage();
      final authState = AuthState(authService: AuthService(baseUrl: 'http://127.0.0.1:1', storage: storage));
      await authState.setDiscreetMode(false);

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('EMERGENCY SOS'), findsNWidgets(2));
      expect(find.text('SAFETY CHECK'), findsNothing);

      await authState.setDiscreetMode(true);
      await tester.pump();

      expect(find.text('SAFETY CHECK'), findsOneWidget);
      expect(find.text('SAFETY OPTIONS'), findsOneWidget);
      expect(find.text('EMERGENCY SOS'), findsNothing);

      await authState.setDiscreetMode(false);
    });

    testWidgets('GestureService LIFO stack keeps parent listening after child route disposes', (WidgetTester tester) async {
      late BuildContext ctxA;
      late BuildContext ctxB;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              Builder(builder: (c) {
                ctxA = c;
                return const SizedBox.shrink();
              }),
              Builder(builder: (c) {
                ctxB = c;
                return const SizedBox.shrink();
              }),
            ],
          ),
        ),
      );

      final gs = GestureService.instance;
      gs.stopListening();
      gs.startListening(ctxA, onSosConfirmed: () async {});
      expect(gs.isListening, isTrue);

      gs.startListening(ctxB, onSosConfirmed: () async {});
      expect(gs.isListening, isTrue);

      gs.stopListening(ctxB);
      expect(gs.isListening, isTrue);

      gs.stopListening(ctxA);
      expect(gs.isListening, isFalse);
    });

    testWidgets('TalkBack semantics expose drawer tooltip, single-label SOS hero/FAB, and Emergency headings', (WidgetTester tester) async {
      final storage = _InMemoryStorage();
      final authState = AuthState(authService: AuthService(baseUrl: 'http://127.0.0.1:1', storage: storage));
      await authState.setDiscreetMode(false);

      final semanticsHandle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.byTooltip('Open navigation menu'), findsOneWidget);
        expect(find.bySemanticsLabel('Emergency SOS. Press for immediate help'), findsOneWidget);
        expect(find.bySemanticsLabel('Trigger emergency SOS'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Trigger emergency SOS')).getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );

        await tester.pumpWidget(const MaterialApp(home: EmergencyPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.bySemanticsLabel('Call National Emergency, 112'), findsOneWidget);
        expect(find.bySemanticsLabel('Call Emergency. Dial 112 for immediate help'), findsNothing);
        expect(find.bySemanticsLabel('Call 112 — Call Emergency. Dial 112 for immediate help'), findsOneWidget);
        expect(
          tester.getSemantics(find.bySemanticsLabel('Call 112 — Call Emergency. Dial 112 for immediate help')).getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(find.bySemanticsLabel('Emergency Helplines'), findsOneWidget);
        expect(find.bySemanticsLabel('Emergency Guidance'), findsOneWidget);
        expect(find.bySemanticsLabel('SOS History'), findsOneWidget);
      } finally {
        semanticsHandle.dispose();
      }
    });

    testWidgets('RegisterPage requires email and PhoneOtpPage shows email-accurate verification copy', (WidgetTester tester) async {
      final storage = _InMemoryStorage();
      final authState = AuthState(authService: AuthService(baseUrl: 'http://127.0.0.1:1', storage: storage));

      await tester.pumpWidget(const MaterialApp(home: RegisterPage()));
      await tester.pump();
      expect(find.text('Email Address *'), findsOneWidget);
      expect(find.text('Email Address (Optional)'), findsNothing);

      await tester.ensureVisible(find.text('Register & Send Verification Code'));
      await tester.tap(find.text('Register & Send Verification Code'));
      await tester.pump();
      expect(find.text('Valid email address is required for verification'), findsOneWidget);

      expect(authState.lastOtpChannel, isNull);
      await tester.pumpWidget(const MaterialApp(home: PhoneOtpPage(phone: '+919876543210')));
      await tester.pump();
      expect(find.text('Account Verification'), findsOneWidget);
      expect(find.textContaining('sent to your email'), findsOneWidget);
      expect(find.textContaining('Code sent via SMS'), findsNothing);
    });
  });
}
