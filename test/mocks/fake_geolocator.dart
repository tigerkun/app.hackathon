import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Zero-codegen mock platform implementation for geolocator.
/// Implements [GeolocatorPlatform] from geolocator_platform_interface to simulate
/// hardware GPS location, permission checking, and fallback scenarios.
class FakeGeolocatorPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements GeolocatorPlatform {
  Position? mockPosition;
  LocationPermission permission = LocationPermission.always;
  bool serviceEnabled = true;
  bool shouldThrowError = false;
  String errorMessage = 'Location service error';

  void reset() {
    mockPosition = null;
    permission = LocationPermission.always;
    serviceEnabled = true;
    shouldThrowError = false;
    errorMessage = 'Location service error';
  }

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    if (shouldThrowError) {
      throw Exception(errorMessage);
    }
    if (!serviceEnabled ||
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location service disabled or permission denied');
    }
    return mockPosition ??
        Position(
          longitude: 77.2090,
          latitude: 28.6139,
          timestamp: DateTime.now(),
          accuracy: 10.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceAndroidLocationManager = false}) async {
    if (shouldThrowError) {
      throw Exception(errorMessage);
    }
    return mockPosition;
  }

  /// Installs this fake instance as the global [GeolocatorPlatform] singleton
  /// and configures the default binary messenger method channel handlers.
  void register() {
    GeolocatorPlatform.instance = this;
    registerBinaryMessengerHandler();
  }

  /// Sets up a mock MethodCallHandler on the BinaryMessenger as a defense-in-depth fallback.
  void registerBinaryMessengerHandler() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'checkPermission') {
          return permission.index;
        } else if (methodCall.method == 'requestPermission') {
          return permission.index;
        } else if (methodCall.method == 'isLocationServiceEnabled') {
          return serviceEnabled;
        } else if (methodCall.method == 'getCurrentPosition') {
          if (shouldThrowError || !serviceEnabled) {
            throw PlatformException(code: 'IO_ERROR', message: errorMessage);
          }
          final pos = mockPosition ??
              Position(
                longitude: 77.2090,
                latitude: 28.6139,
                timestamp: DateTime.now(),
                accuracy: 10.0,
                altitude: 0.0,
                altitudeAccuracy: 0.0,
                heading: 0.0,
                headingAccuracy: 0.0,
                speed: 0.0,
                speedAccuracy: 0.0,
              );
          return <String, dynamic>{
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'timestamp': pos.timestamp.millisecondsSinceEpoch,
            'altitude': pos.altitude,
            'accuracy': pos.accuracy,
            'heading': pos.heading,
            'speed': pos.speed,
            'speed_accuracy': pos.speedAccuracy,
          };
        }
        return null;
      },
    );
  }
}
