package com.grafmod.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val CRITICAL_CHANNEL = "grafmod_critical"
    }

    private val nm get() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "grafmod/system")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "status" -> result.success(status())
                        "setupCriticalChannel" -> {
                            setupCriticalChannel()
                            result.success(null)
                        }
                        "requestIgnoreBattery" -> {
                            val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                                .setData(Uri.parse("package:$packageName"))
                            startActivity(i)
                            result.success(null)
                        }
                        "openBatterySettings" -> {
                            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                            result.success(null)
                        }
                        "openDndAccess" -> {
                            startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                            result.success(null)
                        }
                        "openFullScreenSettings" -> {
                            if (Build.VERSION.SDK_INT >= 34) {
                                startActivity(
                                    Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                                        .setData(Uri.parse("package:$packageName"))
                                )
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("system_error", e.message, null)
                }
            }
    }

    private fun status(): Map<String, Boolean> {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val fullScreen =
            if (Build.VERSION.SDK_INT >= 34) nm.canUseFullScreenIntent() else true
        return mapOf(
            "battery" to pm.isIgnoringBatteryOptimizations(packageName),
            "dnd" to nm.isNotificationPolicyAccessGranted,
            "fullScreen" to fullScreen
        )
    }

    /**
     * Creates the loud alarm channel. A channel's settings are fixed once it
     * exists, so it is recreated each time to pick up the Do Not Disturb
     * override as soon as the user has granted access.
     */
    private fun setupCriticalChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        nm.deleteNotificationChannel(CRITICAL_CHANNEL)
        val channel = NotificationChannel(
            CRITICAL_CHANNEL,
            "Critical alarms",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Loud alarm for critical Grafana alerts."
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), attrs)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
            enableLights(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            if (nm.isNotificationPolicyAccessGranted) setBypassDnd(true)
        }
        nm.createNotificationChannel(channel)
    }
}
