package com.crate.crate

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat.MediaStyle
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Foreground service that owns the MediaSession and the media notification.
 *
 * Flutter drives it through the `crate/media` MethodChannel. The service sends
 * transport commands back to Flutter (`onPlay`, `onPause`, `onNext`, ...), so
 * notification buttons, Bluetooth headsets and the lock screen all control the
 * same playback engine.
 */
class CrateMediaService : Service() {
    companion object {
        const val CHANNEL_ID = "com.crate.crate.playback.v3"
        const val CHANNEL_NAME = "Reproducción"
        const val NOTIFICATION_ID = 4101

        const val ACTION_UPDATE = "com.crate.crate.media.UPDATE"
        const val ACTION_STOP = "com.crate.crate.media.STOP"
        const val ACTION_PLAY = "com.crate.crate.media.PLAY"
        const val ACTION_PAUSE = "com.crate.crate.media.PAUSE"
        const val ACTION_TOGGLE = "com.crate.crate.media.TOGGLE"
        const val ACTION_NEXT = "com.crate.crate.media.NEXT"
        const val ACTION_PREVIOUS = "com.crate.crate.media.PREVIOUS"

        private const val EXTRA_TITLE = "title"
        private const val EXTRA_ARTIST = "artist"
        private const val EXTRA_ALBUM = "album"
        private const val EXTRA_ARTWORK = "artworkPath"
        private const val EXTRA_DURATION = "durationMs"
        private const val EXTRA_POSITION = "positionMs"
        private const val EXTRA_PLAYING = "playing"
        private const val EXTRA_SPEED = "speed"
        private const val EXTRA_CAN_NEXT = "canNext"
        private const val EXTRA_CAN_PREVIOUS = "canPrevious"

        @Volatile
        var bridge: MethodChannel? = null

        @Volatile
        private var instance: CrateMediaService? = null

        fun update(context: Context, data: Map<*, *>) {
            val intent = Intent(context, CrateMediaService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TITLE, data["title"] as? String ?: "")
                putExtra(EXTRA_ARTIST, data["artist"] as? String ?: "")
                putExtra(EXTRA_ALBUM, data["album"] as? String ?: "")
                putExtra(EXTRA_ARTWORK, data["artworkPath"] as? String)
                putExtra(EXTRA_DURATION, (data["durationMs"] as? Number)?.toLong() ?: 0L)
                putExtra(EXTRA_POSITION, (data["positionMs"] as? Number)?.toLong() ?: 0L)
                putExtra(EXTRA_PLAYING, data["playing"] as? Boolean ?: false)
                putExtra(EXTRA_SPEED, (data["speed"] as? Number)?.toFloat() ?: 1f)
                putExtra(EXTRA_CAN_NEXT, data["canNext"] as? Boolean ?: false)
                putExtra(EXTRA_CAN_PREVIOUS, data["canPrevious"] as? Boolean ?: false)
            }
            if (instance == null) {
                try {
                    ContextCompat.startForegroundService(context, intent)
                } catch (_: Exception) {
                    try {
                        context.startService(intent)
                    } catch (_: Exception) {
                    }
                }
            } else {
                try {
                    context.startService(intent)
                } catch (_: Exception) {
                }
            }
        }

        fun stop(context: Context) {
            if (instance == null) return
            try {
                context.startService(
                    Intent(context, CrateMediaService::class.java).apply {
                        action = ACTION_STOP
                    },
                )
            } catch (_: Exception) {
            }
        }
    }

    private lateinit var session: MediaSessionCompat
    private lateinit var audioManager: AudioManager

    private var foregroundStarted = false
    private var playing = false
    private var title = ""
    private var artist = ""
    private var album = ""
    private var durationMs = 0L
    private var positionMs = 0L
    private var speed = 1f
    private var canNext = false
    private var canPrevious = false
    private var artworkPath: String? = null
    private var artwork: Bitmap? = null
    private var hasAudioFocus = false
    private var focusRequest: AudioFocusRequest? = null
    private var released = false

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK,
            -> {
                hasAudioFocus = false
                if (playing) {
                    bridge?.invokeMethod("onPause", null)
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createChannel()
        session = MediaSessionCompat(this, "CrateMediaSession").apply {
            setFlags(
                MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                    MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
            )
            setCallback(
                object : MediaSessionCompat.Callback() {
                    override fun onPlay() {
                        bridge?.invokeMethod("onPlay", null)
                    }

                    override fun onPause() {
                        bridge?.invokeMethod("onPause", null)
                    }

                    override fun onSkipToNext() {
                        bridge?.invokeMethod("onNext", null)
                    }

                    override fun onSkipToPrevious() {
                        bridge?.invokeMethod("onPrevious", null)
                    }

                    override fun onStop() {
                        bridge?.invokeMethod("onStop", null)
                    }

                    override fun onSeekTo(pos: Long) {
                        bridge?.invokeMethod("onSeek", pos)
                    }
                },
            )
            isActive = true
            setSessionActivity(sessionActivityPending())
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                bridge?.invokeMethod("onStop", null)
                teardown()
                return START_NOT_STICKY
            }

            ACTION_PLAY -> bridge?.invokeMethod("onPlay", null)
            ACTION_PAUSE -> bridge?.invokeMethod("onPause", null)
            ACTION_TOGGLE -> bridge?.invokeMethod("onToggle", null)
            ACTION_NEXT -> bridge?.invokeMethod("onNext", null)
            ACTION_PREVIOUS -> bridge?.invokeMethod("onPrevious", null)
            ACTION_UPDATE -> applyUpdate(intent)
        }

        if (!foregroundStarted) {
            startForeground(NOTIFICATION_ID, buildNotification())
            foregroundStarted = true
        } else {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification())
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        teardown()
        super.onDestroy()
    }

    private fun teardown() {
        if (released) return
        released = true
        if (::session.isInitialized) {
            session.isActive = false
            session.release()
        }
        abandonFocus()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        foregroundStarted = false
        instance = null
        stopSelf()
    }

    private fun applyUpdate(intent: Intent) {
        title = intent.getStringExtra(EXTRA_TITLE) ?: ""
        artist = intent.getStringExtra(EXTRA_ARTIST) ?: ""
        album = intent.getStringExtra(EXTRA_ALBUM) ?: ""
        durationMs = intent.getLongExtra(EXTRA_DURATION, 0L)
        positionMs = intent.getLongExtra(EXTRA_POSITION, 0L).coerceAtLeast(0L)
        playing = intent.getBooleanExtra(EXTRA_PLAYING, false)
        speed = intent.getFloatExtra(EXTRA_SPEED, 1f).coerceIn(0.25f, 4f)
        canNext = intent.getBooleanExtra(EXTRA_CAN_NEXT, false)
        canPrevious = intent.getBooleanExtra(EXTRA_CAN_PREVIOUS, false)

        val path = intent.getStringExtra(EXTRA_ARTWORK)
        if (path != artworkPath) {
            artworkPath = path
            artwork = loadArtwork(path)
        }

        if (playing) {
            requestFocus()
        } else {
            abandonFocus()
        }

        updateSession()
    }

    private fun updateSession() {
        val metadata = MediaMetadataCompat.Builder()
            .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
            .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, artist)
            .putString(MediaMetadataCompat.METADATA_KEY_ALBUM, album)
            .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs)
            .apply {
                artwork?.let {
                    putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, it)
                    putBitmap(MediaMetadataCompat.METADATA_KEY_ART, it)
                    putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, it)
                }
            }
            .build()
        session.setMetadata(metadata)

        val actions = PlaybackStateCompat.ACTION_PLAY or
            PlaybackStateCompat.ACTION_PAUSE or
            PlaybackStateCompat.ACTION_PLAY_PAUSE or
            PlaybackStateCompat.ACTION_STOP or
            PlaybackStateCompat.ACTION_SEEK_TO or
            (if (canNext) PlaybackStateCompat.ACTION_SKIP_TO_NEXT else 0L) or
            (if (canPrevious) PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS else 0L)

        session.setPlaybackState(
            PlaybackStateCompat.Builder()
                .setActions(actions)
                .setState(
                    if (playing) {
                        PlaybackStateCompat.STATE_PLAYING
                    } else {
                        PlaybackStateCompat.STATE_PAUSED
                    },
                    positionMs,
                    if (playing) speed else 1f,
                    SystemClock.elapsedRealtime(),
                )
                .build(),
        )
        session.isActive = true
    }

    private fun buildNotification(): Notification {
        val openPending = sessionActivityPending()

        val previousPending = actionPending(ACTION_PREVIOUS, 11)
        val togglePending = actionPending(ACTION_TOGGLE, 12)
        val nextPending = actionPending(ACTION_NEXT, 13)
        val stopPending = actionPending(ACTION_STOP, 14)

        val subtitle = when {
            artist.isNotBlank() && album.isNotBlank() && artist != album ->
                "$artist · $album"

            artist.isNotBlank() -> artist
            else -> album
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_crate_note)
            .setContentTitle(title.ifBlank { "Crate" })
            .setContentText(subtitle)
            .setSubText(album.takeIf { it.isNotBlank() && it != artist })
            .setContentIntent(openPending)
            .setDeleteIntent(stopPending)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setShowWhen(false)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setOngoing(playing)
            .addAction(R.drawable.ic_crate_previous, "Anterior", previousPending)
            .addAction(
                if (playing) R.drawable.ic_crate_pause else R.drawable.ic_crate_play,
                if (playing) "Pausa" else "Reproducir",
                togglePending,
            )
            .addAction(R.drawable.ic_crate_next, "Siguiente", nextPending)
            .addAction(R.drawable.ic_crate_stop, "Detener", stopPending)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(
                NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE,
            )
        }

        artwork?.let { builder.setLargeIcon(it) }

        val style = MediaStyle().setMediaSession(session.sessionToken)
        if (Build.VERSION.SDK_INT < 33) {
            style.setShowActionsInCompactView(0, 1, 2)
        }
        builder.setStyle(style)
        return builder.build()
    }

    private fun sessionActivityPending(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(this, 10, intent, pendingFlags())
    }

    private fun actionPending(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, CrateMediaService::class.java).apply {
            this.action = action
        }
        return PendingIntent.getService(this, requestCode, intent, pendingFlags())
    }

    private fun pendingFlags(): Int {
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return flags
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Controles de reproducción de Crate"
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun loadArtwork(path: String?): Bitmap? {
        if (path.isNullOrBlank()) return null
        return try {
            val file = File(path)
            if (!file.exists()) return null
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sampleSize = 1
            val largest = maxOf(bounds.outWidth, bounds.outHeight)
            while (largest / sampleSize > 720) {
                sampleSize *= 2
            }
            val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
            BitmapFactory.decodeFile(path, options)
        } catch (_: Exception) {
            null
        }
    }

    private fun requestFocus() {
        if (hasAudioFocus) return
        val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
        hasAudioFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocus() {
        if (!hasAudioFocus) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
        hasAudioFocus = false
    }
}
