package com.grafmod.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.RingtoneManager
import android.os.Build

/**
 * Fired by the system alarm clock when a 15 minute snooze ends. It works even
 * while the phone is asleep, which a timer inside the app does not. It rings
 * the critical alarm again and opens the alarm page over the lock screen. The
 * background service then re-checks Grafana and clears the alarm if the alert
 * has resolved in the meantime.
 */
class SnoozeReceiver : BroadcastReceiver() {
    companion object {
        const val NOTIFICATION_ID = 9001 // same id the app uses for the alarm
    }

    override fun onReceive(context: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "CRITICAL ALERT"
        val body = intent.getStringExtra("body") ?: "A critical alert is firing in Grafana."
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(MainActivity.CRITICAL_CHANNEL) == null) {
            val ch = NotificationChannel(
                MainActivity.CRITICAL_CHANNEL,
                "Critical alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Loud alarm for critical Grafana alerts."
                setSound(
                    alarmUri,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(ch)
        }

        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("payload", MainActivity.ALARM_PAYLOAD)
        }
        var piFlags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= 23) piFlags = piFlags or PendingIntent.FLAG_IMMUTABLE
        val pi = PendingIntent.getActivity(context, NOTIFICATION_ID, open, piFlags)

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, MainActivity.CRITICAL_CHANNEL)
        } else {
            Notification.Builder(context)
                .setPriority(Notification.PRIORITY_MAX)
                .setSound(alarmUri, AudioManager.STREAM_ALARM)
                .setVibrate(longArrayOf(0, 800, 400, 800, 400, 800))
        }
        val n = builder
            .setSmallIcon(R.drawable.ic_stat_grafmod)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(pi)
            .setFullScreenIntent(pi, true)
            .setOngoing(true)
            .setAutoCancel(false)
            .build()
        // 4 = FLAG_INSISTENT: keep sounding until the alarm is dismissed.
        n.flags = n.flags or Notification.FLAG_INSISTENT
        nm.notify(NOTIFICATION_ID, n)
    }
}
