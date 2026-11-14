package com.grafmod.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.PendingIntent
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val CRITICAL_CHANNEL = "grafmod_critical"

        // Payload of the critical alarm notification (see AlarmNotifier).
        const val ALARM_PAYLOAD = "grafmod_alarm"
    }

    /** True while the app is showing the alarm page over the lock screen. */
    private var alarmMode = false

    /** True while the alarm page is on screen. */
    private var ringing = false

    private var systemChannel: MethodChannel? = null
    private var screenOffReceiver: BroadcastReceiver? = null

    /**
     * While the alarm page is up the screen is kept on, so the only way it
     * goes dark is the power button. That is reported to Dart, which snoozes
     * the alarm.
     */
    private fun setRingingNative(on: Boolean) {
        ringing = on
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            if (screenOffReceiver == null) {
                val r = object : BroadcastReceiver() {
                    override fun onReceive(context: Context?, intent: Intent?) {
                        if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                            systemChannel?.invokeMethod("screenOff", null)
                        }
                    }
                }
                screenOffReceiver = r
                val f = IntentFilter(Intent.ACTION_SCREEN_OFF)
                if (Build.VERSION.SDK_INT >= 33) {
                    registerReceiver(r, f, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    registerReceiver(r, f)
                }
            }
        } else {
            screenOffReceiver?.let {
                try { unregisterReceiver(it) } catch (_: Exception) {}
            }
            screenOffReceiver = null
            if (!alarmMode) window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun onDestroy() {
        screenOffReceiver?.let {
            try { unregisterReceiver(it) } catch (_: Exception) {}
        }
        screenOffReceiver = null
        super.onDestroy()
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        // The alarm cannot be backed out of; use "Dismiss alarm".
        if (ringing) return
        super.onBackPressed()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAlarmIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleAlarmIntent(intent)
    }

    /**
     * The critical alarm notification starts this activity as a full-screen
     * intent. Only then is the app allowed over the lock screen and the
     * screen turned on, so opening the app normally never skips the lock.
     */
    private fun handleAlarmIntent(i: Intent?) {
        if (i?.getStringExtra("payload") == ALARM_PAYLOAD) enterAlarmMode()
    }

    private fun enterAlarmMode() {
        alarmMode = true
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun endAlarmMode(moveToBack: Boolean) {
        if (!alarmMode) return
        alarmMode = false
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        // Back to the lock screen; the app is not left open behind it.
        if (moveToBack && km.isKeyguardLocked) moveTaskToBack(true)
    }

    /** Asks the user to unlock the phone; replies true once it is unlocked. */
    private fun dismissKeyguard(result: MethodChannel.Result) {
        val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        if (Build.VERSION.SDK_INT >= 26 && km.isKeyguardLocked) {
            km.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() = result.success(true)
                override fun onDismissCancelled() = result.success(false)
                override fun onDismissError() = result.success(false)
            })
        } else {
            result.success(true)
        }
    }

    private val nm get() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun snoozePendingIntent(title: String?, body: String?): PendingIntent {
        val i = Intent(this, SnoozeReceiver::class.java)
        if (title != null) i.putExtra("title", title)
        if (body != null) i.putExtra("body", body)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) flags = flags or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(this, 9002, i, flags)
    }

    /**
     * Sets a system alarm clock for the end of a snooze. Alarm clocks are
     * allowed to fire while the phone is asleep or in Doze, and need no extra
     * permission.
     */
    private fun scheduleSnooze(at: Long, title: String?, body: String?) {
        if (at <= 0L) return
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) flags = flags or PendingIntent.FLAG_IMMUTABLE
        val show = PendingIntent.getActivity(this, 9003, Intent(this, MainActivity::class.java), flags)
        am.setAlarmClock(AlarmManager.AlarmClockInfo(at, show), snoozePendingIntent(title, body))
    }

    private fun cancelSnooze() {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(snoozePendingIntent(null, null))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "grafmod/system")
        systemChannel = channel
        channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "status" -> result.success(status())
                        "endAlarm" -> {
                            val back = call.argument<Boolean>("moveToBack") ?: true
                            endAlarmMode(back)
                            result.success(null)
                        }
                        "setRinging" -> {
                            setRingingNative(call.argument<Boolean>("ringing") ?: false)
                            result.success(null)
                        }
                        "scheduleSnooze" -> {
                            scheduleSnooze(
                                call.argument<Number>("at")?.toLong() ?: 0L,
                                call.argument<String>("title"),
                                call.argument<String>("body")
                            )
                            result.success(null)
                        }
                        "cancelSnooze" -> {
                            cancelSnooze()
                            result.success(null)
                        }
                        "dismissKeyguard" -> dismissKeyguard(result)
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
