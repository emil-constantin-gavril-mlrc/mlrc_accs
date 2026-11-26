package com.isvisoft.flutter_screen_recording

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import android.os.Binder

class ForegroundService : Service() {
    private val CHANNEL_ID = "ForegroundService Kotlin"

    companion object {
        fun startService(context: Context, title: String, message: String) {
            val startIntent = Intent(context, ForegroundService::class.java)
            startIntent.putExtra("messageExtra", message)
            startIntent.putExtra("titleExtra", title)
            ContextCompat.startForegroundService(context, startIntent)
        }

        fun stopService(context: Context) {
            context.stopService(Intent(context, ForegroundService::class.java))
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return try {
            startForegroundServiceWithNotification(intent)
            START_NOT_STICKY
        } catch (err: Exception) {
            Log.e("ScreenRecordingPlugin", "Could not start projection foreground service", err)
            stopSelf(startId)
            START_NOT_STICKY
        }
    }

    private fun startForegroundServiceWithNotification(intent: Intent?) {
        var title = intent?.getStringExtra("titleExtra") ?: "Flutter Screen Recording"
        var message = intent?.getStringExtra("messageExtra") ?: ""

        createNotificationChannel()
        val notificationIntent = Intent(this, FlutterScreenRecordingPlugin::class.java)

        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent, PendingIntent.FLAG_MUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(android.R.drawable.presence_video_online)
            .setContentIntent(pendingIntent)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                1,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(1, notification)
        }
    }

    override fun onBind(intent: Intent): IBinder {
        return Binder()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID, "Foreground Service Channel", NotificationManager.IMPORTANCE_DEFAULT
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager!!.createNotificationChannel(serviceChannel)
        }
    }
}