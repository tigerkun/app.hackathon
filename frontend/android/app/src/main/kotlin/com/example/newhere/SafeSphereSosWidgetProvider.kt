package com.example.newhere

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews

/**
 * Home Screen & Keyguard Emergency SOS Widget.
 * Launches /emergency directly (bypassing auth/PIN/onboarding) or opens the
 * native tel:112 dialer in one tap.
 */
class SafeSphereSosWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        const val EXTRA_QUICK_ROUTE = "safesphere_route"
        const val EXTRA_SHOW_WHEN_LOCKED = "show_when_locked"
        const val ROUTE_EMERGENCY = "/emergency"

        fun createEmergencyLaunchIntent(context: Context): Intent {
            return Intent(context, MainActivity::class.java).apply {
                action = "com.example.newhere.ACTION_EMERGENCY_SOS"
                putExtra(EXTRA_QUICK_ROUTE, ROUTE_EMERGENCY)
                putExtra(EXTRA_SHOW_WHEN_LOCKED, true)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
            }
        }

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.safesphere_sos_widget)

            val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val sosPendingIntent = PendingIntent.getActivity(
                context,
                11201,
                createEmergencyLaunchIntent(context),
                immutableFlag
            )
            views.setOnClickPendingIntent(R.id.btn_widget_sos, sosPendingIntent)

            val dialIntent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:112")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val dialPendingIntent = PendingIntent.getActivity(
                context,
                11202,
                dialIntent,
                immutableFlag
            )
            views.setOnClickPendingIntent(R.id.btn_widget_dial_112, dialPendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        fun isPinSupported(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
            val manager = AppWidgetManager.getInstance(context)
            return manager != null && manager.isRequestPinAppWidgetSupported
        }

        fun requestPin(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
            val manager = AppWidgetManager.getInstance(context) ?: return false
            if (!manager.isRequestPinAppWidgetSupported) return false
            val provider = ComponentName(context, SafeSphereSosWidgetProvider::class.java)
            return manager.requestPinAppWidget(provider, null, null)
        }
    }
}
