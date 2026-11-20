// Hardware panic gesture interceptor (F5-1)
// Implements long-press volume-down and shake-to-SOS with intermediate confirmation
// and mandatory 5-second countdown cancel window before SOS dispatch.
// Honest gating: degrades silently if sensors/plugins are not supported by platform.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:volume_controller/volume_controller.dart';
import '../data/auth_state.dart';
import '../pages/emergency_page.dart';

class GestureService {
  GestureService._internal();
  static final GestureService instance = GestureService._internal();

  StreamSubscription? _accelerometerSub;
  Timer? _volumeHoldTimer;
  bool _isListening = false;
  bool _isPromptOpen = false;

  bool _sensorsAvailable = true;
  bool _volumeAvailable = true;

  bool get isListening => _isListening;
  bool get sensorsAvailable => _sensorsAvailable;
  bool get volumeAvailable => _volumeAvailable;

  // Shake detection state: requires 3 rapid reversals (> 24 m/s^2) in 1.2s to prevent false drops/bumps
  int _shakeCount = 0;
  DateTime? _lastShakeTimestamp;
  static const double _shakeThreshold = 24.0;
  static const int _requiredShakes = 3;
  static const Duration _shakeWindow = Duration(milliseconds: 1200);

  // Volume detection state
  double? _lastVolume;
  DateTime? _volumeDownStart;

  void startListening(BuildContext context, {required Future<void> Function() onSosConfirmed}) {
    if (_isListening) return;
    _isListening = true;

    _initShakeDetection(context, onSosConfirmed);
    _initVolumeDetection(context, onSosConfirmed);
  }

  void stopListening() {
    _isListening = false;
    _accelerometerSub?.cancel();
    _accelerometerSub = null;
    _volumeHoldTimer?.cancel();
    _volumeHoldTimer = null;
    try {
      VolumeController().removeListener();
    } catch (_) {}
  }

  void _initShakeDetection(BuildContext context, Future<void> Function() onSosConfirmed) {
    try {
      _accelerometerSub = accelerometerEventStream().listen(
        (AccelerometerEvent event) {
          final authState = AuthState();
          if (!authState.emergencyGesturesEnabled) return;
          if (_isPromptOpen || !context.mounted) return;

          final double magnitude = math.sqrt(
            event.x * event.x + event.y * event.y + event.z * event.z,
          );

          if (magnitude > _shakeThreshold) {
            final now = DateTime.now();
            if (_lastShakeTimestamp == null ||
                now.difference(_lastShakeTimestamp!) > _shakeWindow) {
              _shakeCount = 1;
              _lastShakeTimestamp = now;
            } else {
              _shakeCount++;
              if (_shakeCount >= _requiredShakes) {
                _shakeCount = 0;
                _lastShakeTimestamp = null;
                _handleShakeDetected(context, onSosConfirmed);
              }
            }
          }
        },
        onError: (_) {
          _sensorsAvailable = false;
        },
        cancelOnError: false,
      );
    } catch (_) {
      _sensorsAvailable = false;
    }
  }

  void _initVolumeDetection(BuildContext context, Future<void> Function() onSosConfirmed) {
    try {
      VolumeController().listener((double volume) {
        final authState = AuthState();
        if (!authState.emergencyGesturesEnabled) return;
        if (_isPromptOpen || !context.mounted) return;

        final prev = _lastVolume;
        _lastVolume = volume;

        // Long-press volume down: volume drops or remains pressed down at 0
        if (prev != null && (volume < prev || (volume == 0.0 && prev == 0.0))) {
          _volumeDownStart ??= DateTime.now();
          _volumeHoldTimer?.cancel();
          _volumeHoldTimer = Timer(const Duration(milliseconds: 1500), () {
            if (_isListening && context.mounted && !_isPromptOpen) {
              _volumeDownStart = null;
              _launchCountdownDialog(context, onSosConfirmed, triggerReason: "Volume-down long-press");
            }
          });
        } else {
          _volumeDownStart = null;
          _volumeHoldTimer?.cancel();
        }
      });
    } catch (_) {
      _volumeAvailable = false;
    }
  }

  Future<void> _handleShakeDetected(BuildContext context, Future<void> Function() onSosConfirmed) async {
    if (_isPromptOpen || !context.mounted) return;
    _isPromptOpen = true;

    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    // Intermediate confirmation so drops/bumps don't false-alarm
    final shouldProceed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.vibration, color: Colors.amber, size: 28),
            SizedBox(width: 8),
            Text("Shake Detected"),
          ],
        ),
        content: const Text(
          "A rapid phone shake was detected. Do you want to initiate an Emergency SOS broadcast?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Dismiss", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Confirm SOS"),
          ),
        ],
      ),
    );

    _isPromptOpen = false;

    if (shouldProceed == true && context.mounted) {
      await _launchCountdownDialog(context, onSosConfirmed, triggerReason: "Shake gesture");
    }
  }

  Future<void> _launchCountdownDialog(
    BuildContext context,
    Future<void> Function() onSosConfirmed, {
    required String triggerReason,
  }) async {
    if (_isPromptOpen || !context.mounted) return;
    _isPromptOpen = true;

    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    // Both gestures MUST respect the 5s cancel dialog — hardware triggers open the dialog, never bypass.
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SosCountdownDialog(durationSeconds: 5),
    );

    _isPromptOpen = false;

    if (confirmed == true && context.mounted) {
      await onSosConfirmed();
    }
  }
}
