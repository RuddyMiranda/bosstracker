package com.ruddy.osrbosstracker

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    createRespawnNotificationChannel()
  }

  private fun createRespawnNotificationChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val soundUri = Settings.System.DEFAULT_NOTIFICATION_URI
    val ch = NotificationChannel(
      "boss_respawn_soon",
      "Respawn de bosses",
      NotificationManager.IMPORTANCE_HIGH
    ).apply {
      description = "Aviso cuando un boss está por respawnear (FCM debe usar este canal)."
      setSound(
        soundUri,
        AudioAttributes.Builder()
          .setUsage(AudioAttributes.USAGE_NOTIFICATION)
          .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
          .build()
      )
      enableVibration(true)
    }
    val nm = getSystemService(NotificationManager::class.java)
    nm.createNotificationChannel(ch)
  }
}
