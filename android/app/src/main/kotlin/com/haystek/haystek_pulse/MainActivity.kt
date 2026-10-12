package com.haystek.haystek_pulse

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A high-importance channel plays the phone's notification sound
        // and shows the notification at the top of the screen.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "haystek_alerts",
                "Haystek notifications",
                NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "Weekly Pulse and Suggestion Box updates"
            channel.enableVibration(true)
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }
}