package com.example.newhere

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var methodChannel: MethodChannel? = null
    private var pendingQuickRoute: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        handleEmergencyIntentFlags(intent)
        captureQuickRoute(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleEmergencyIntentFlags(intent)
        val route = captureQuickRoute(intent)
        if (route != null) {
            methodChannel?.invokeMethod("onQuickRoute", route)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.safesphere/quick_access"
        )
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeInitialQuickRoute" -> {
                    val route = pendingQuickRoute
                    pendingQuickRoute = null
                    result.success(route)
                }
                "isPinWidgetSupported" -> {
                    result.success(SafeSphereSosWidgetProvider.isPinSupported(this))
                }
                "requestPinWidget" -> {
                    result.success(SafeSphereSosWidgetProvider.requestPin(this))
                }
                "isQuickTilePinSupported" -> {
                    result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                }
                "requestAddQuickTile" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        SafeSphereSosTileService.requestAddTile(this) { status ->
                            result.success(status)
                        }
                    } else {
                        result.success("unsupported")
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun captureQuickRoute(intent: Intent?): String? {
        val route = intent?.getStringExtra(SafeSphereSosWidgetProvider.EXTRA_QUICK_ROUTE)
            ?: if (intent?.action == "com.example.newhere.ACTION_EMERGENCY_SOS") {
                SafeSphereSosWidgetProvider.ROUTE_EMERGENCY
            } else {
                null
            }
        if (route == SafeSphereSosWidgetProvider.ROUTE_EMERGENCY) {
            pendingQuickRoute = route
            return route
        }
        return null
    }

    private fun handleEmergencyIntentFlags(intent: Intent?) {
        val route = intent?.getStringExtra(SafeSphereSosWidgetProvider.EXTRA_QUICK_ROUTE)
            ?: if (intent?.action == "com.example.newhere.ACTION_EMERGENCY_SOS") {
                SafeSphereSosWidgetProvider.ROUTE_EMERGENCY
            } else {
                null
            }
        val allowLocked =
            intent?.getBooleanExtra(SafeSphereSosWidgetProvider.EXTRA_SHOW_WHEN_LOCKED, false) == true ||
                intent?.getStringExtra(SafeSphereSosWidgetProvider.EXTRA_SHOW_WHEN_LOCKED)
                    ?.equals("true", ignoreCase = true) == true
        if (route == SafeSphereSosWidgetProvider.ROUTE_EMERGENCY && allowLocked) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            }
        }
    }
}
