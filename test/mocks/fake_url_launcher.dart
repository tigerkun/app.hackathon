import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Zero-codegen mock platform implementation for url_launcher.
/// Implements [UrlLauncherPlatform] from url_launcher_platform_interface and
/// provides binary messenger interception for telephony and URL launches.
class FakeUrlLauncherPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  final List<String> launchedUrls = <String>[];
  final List<LaunchOptions> launchOptionsList = <LaunchOptions>[];

  bool canLaunchResult = true;
  bool launchResult = true;

  String? get lastLaunchedUrl =>
      launchedUrls.isNotEmpty ? launchedUrls.last : null;

  void reset() {
    launchedUrls.clear();
    launchOptionsList.clear();
    canLaunchResult = true;
    launchResult = true;
  }

  @override
  Future<bool> canLaunch(String url) async => canLaunchResult;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    launchOptionsList.add(options);
    return launchResult;
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
  }) async {
    launchedUrls.add(url);
    return launchResult;
  }

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => true;

  @override
  Future<void> closeWebView() async {}

  /// Installs this fake instance as the global [UrlLauncherPlatform] singleton
  /// and configures the default binary messenger method channel handler.
  void register() {
    UrlLauncherPlatform.instance = this;
    registerBinaryMessengerHandler();
  }

  /// Sets up a mock MethodCallHandler on the BinaryMessenger as a defense-in-depth fallback.
  void registerBinaryMessengerHandler() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'canLaunch') {
          return canLaunchResult;
        } else if (methodCall.method == 'launch') {
          final url = methodCall.arguments['url'] as String?;
          if (url != null) {
            launchedUrls.add(url);
          }
          return launchResult;
        }
        return null;
      },
    );
  }
}
