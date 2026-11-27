package com.example.newhere

import android.app.PendingIntent
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Android Quick Settings Tile (accessible from both Lock Screen & Home shade).
 * Tapping launches SafeSphere directly into /emergency without PIN/auth gating.
 */
@RequiresApi(Build.VERSION_CODES.N)
class SafeSphereSosTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        tile.state = Tile.STATE_ACTIVE
        tile.label = "SafeSphere SOS"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = "Emergency & 112"
        }
        tile.updateTile()
    }

    override fun onClick() {
        super.onClick()
        val intent = SafeSphereSosWidgetProvider.createEmergencyLaunchIntent(this)
        if (Build.VERSION.SDK_INT >= 34) {
            val pi = PendingIntent.getActivity(
                this,
                11203,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            startActivityAndCollapse(pi)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    companion object {
        fun requestAddTile(context: Context, onResult: (String) -> Unit) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                onResult("unsupported")
                return
            }
            val manager = context.getSystemService(StatusBarManager::class.java)
            if (manager == null) {
                onResult("unsupported")
                return
            }
            val component = ComponentName(context, SafeSphereSosTileService::class.java)
            val icon = Icon.createWithResource(context, R.drawable.ic_sos_tile)
            manager.requestAddTileService(
                component,
                "SafeSphere SOS",
                icon,
                context.mainExecutor
            ) { resultCode ->
                val status = when (resultCode) {
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED -> "added"
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED -> "already_added"
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_NOT_ADDED -> "declined"
                    else -> "requested"
                }
                onResult(status)
            }
        }
    }
}
