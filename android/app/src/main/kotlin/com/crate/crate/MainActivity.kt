package com.crate.crate

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    companion object {
        private const val ENGINE_ID = "crate_main_engine"
        private const val TEST_CHANNEL_ID = "com.crate.crate.test"
    }

    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "crate/permissions",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureAudioPermission" -> ensureAudioPermission(result)
                "ensureNotificationPermission" -> ensureNotificationPermission(result)
                "notificationStatus" -> result.success(notificationStatus())
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                "postTestNotification" -> result.success(postTestNotification())
                else -> result.notImplemented()
            }
        }

        val mediaChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "crate/media",
        )
        mediaChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val data = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                    CrateMediaService.update(this, data)
                    result.success(null)
                }
                "stop" -> {
                    CrateMediaService.stop(this)
                    result.success(null)
                }
                "notificationStatus" -> result.success(notificationStatus())
                "requestNotificationPermission" ->
                    ensureNotificationPermission(result)
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                "postTestNotification" -> result.success(postTestNotification())
                else -> result.notImplemented()
            }
        }
        CrateMediaService.bridge = mediaChannel

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "crate/analysis",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "analyzeNative" -> {
                    val path = call.argument<String>("path")
                    val scanSeconds = call.argument<Int>("scanSeconds") ?: 30
                    if (path == null) {
                        result.error("analysis", "path missing", null)
                    } else {
                        analyzeNative(path, scanSeconds, result)
                    }
                }
                "decodeToWav" -> {
                    val path = call.argument<String>("path")
                    val scanSeconds = call.argument<Int>("scanSeconds") ?: 30
                    if (path == null) {
                        result.error("decode", "path missing", null)
                    } else {
                        decodeToWav(path, scanSeconds, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ensureAudioPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.success(true)
            return
        }
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(permission), 1001)
    }

    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        val permission = Manifest.permission.POST_NOTIFICATIONS
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        pendingNotificationResult = result
        requestPermissions(arrayOf(permission), 1002)
    }

    private fun notificationStatus(): Map<String, Any?> {
        val manager = getSystemService(NotificationManager::class.java)
        val notificationsEnabled = manager.areNotificationsEnabled()
        val permissionGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.getNotificationChannel(CrateMediaService.CHANNEL_ID)
        } else {
            null
        }
        val importance = channel?.importance ?: -1
        return mapOf(
            "enabled" to notificationsEnabled,
            "permissionGranted" to permissionGranted,
            "channelExists" to (channel != null),
            "channelImportance" to importance,
            "channelBlocked" to (
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    channel != null &&
                    importance == NotificationManager.IMPORTANCE_NONE
                ),
        )
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:$packageName"),
            )
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun postTestNotification(): Boolean {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (manager.getNotificationChannel(TEST_CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        TEST_CHANNEL_ID,
                        "Pruebas de Crate",
                        NotificationManager.IMPORTANCE_DEFAULT,
                    ),
                )
            }
        }
        val notification = NotificationCompat.Builder(this, TEST_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_crate_note)
            .setContentTitle("Crate")
            .setContentText("Las notificaciones funcionan correctamente.")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .build()
        manager.notify(9001, notification)
        return true
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        } else if (requestCode == 1002) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationResult?.success(granted)
            pendingNotificationResult = null
        }
    }

    private fun analyzeNative(
        path: String,
        scanSeconds: Int,
        result: MethodChannel.Result,
    ) {
        Thread {
            val analysis = try {
                NativeAnalyzer.analyze(path, scanSeconds)
            } catch (_: Exception) {
                null
            }
            runOnUiThread {
                if (analysis != null) {
                    result.success(analysis)
                } else {
                    result.error("analysis", "native analysis failed", null)
                }
            }
        }.start()
    }

    private fun decodeToWav(
        path: String,
        scanSeconds: Int,
        result: MethodChannel.Result,
    ) {
        Thread {
            var extractor: MediaExtractor? = null
            var codec: MediaCodec? = null
            try {
                extractor = MediaExtractor()
                extractor.setDataSource(path)
                var trackIndex = -1
                var format: MediaFormat? = null
                for (index in 0 until extractor.trackCount) {
                    val candidate = extractor.getTrackFormat(index)
                    val mime = candidate.getString(MediaFormat.KEY_MIME) ?: continue
                    if (mime.startsWith("audio/")) {
                        trackIndex = index
                        format = candidate
                        break
                    }
                }
                if (trackIndex < 0 || format == null) {
                    throw IllegalArgumentException("No audio track")
                }
                extractor.selectTrack(trackIndex)

                val fullDurationSeconds = try {
                    format.getLong(MediaFormat.KEY_DURATION) / 1_000_000.0
                } catch (_: Exception) {
                    0.0
                }

                val mime = format.getString(MediaFormat.KEY_MIME)!!
                var outputSampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                var outputChannels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                codec = MediaCodec.createDecoderByType(mime)
                codec.configure(format, null, null, 0)
                codec.start()

                val targetRate = 11025
                var sourceRate = outputSampleRate
                var resampleStep = if (sourceRate > targetRate) {
                    sourceRate / targetRate.toDouble()
                } else {
                    1.0
                }
                var resamplePhase = 0.0
                var resampleSum = 0.0
                var resampleCount = 0

                val output = File(cacheDir, "analysis_${System.currentTimeMillis()}.wav")
                var totalBytes = 0
                val maxSeconds = if (scanSeconds <= 0) {
                    600.0
                } else {
                    scanSeconds + 30.0
                }
                val maxBytes = (maxSeconds * targetRate * 2).toInt()

                FileOutputStream(output).use { stream ->
                    stream.write(ByteArray(44))
                    val info = MediaCodec.BufferInfo()
                    var inputDone = false
                    var outputDone = false

                    while (!outputDone) {
                        if (!inputDone) {
                            val inputIndex = codec.dequeueInputBuffer(10000)
                            if (inputIndex >= 0) {
                                val input = codec.getInputBuffer(inputIndex)!!
                                val size = extractor.readSampleData(input, 0)
                                if (size < 0) {
                                    codec.queueInputBuffer(
                                        inputIndex,
                                        0,
                                        0,
                                        0,
                                        MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                    )
                                    inputDone = true
                                } else {
                                    codec.queueInputBuffer(
                                        inputIndex,
                                        0,
                                        size,
                                        extractor.sampleTime,
                                        0,
                                    )
                                    extractor.advance()
                                }
                            }
                        }

                        val outputIndex = codec.dequeueOutputBuffer(info, 10000)
                        if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            val outputFormat = codec.outputFormat
                            outputSampleRate =
                                outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                            outputChannels =
                                outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                            sourceRate = outputSampleRate
                            resampleStep = if (sourceRate > targetRate) {
                                sourceRate / targetRate.toDouble()
                            } else {
                                1.0
                            }
                            continue
                        }
                        if (outputIndex >= 0) {
                            val buffer = codec.getOutputBuffer(outputIndex)!!
                            if (info.size > 0) {
                                val bytes = ByteArray(info.size)
                                buffer.position(info.offset)
                                buffer.get(bytes)
                                val shorts = ByteBuffer.wrap(bytes)
                                    .order(ByteOrder.nativeOrder())
                                    .asShortBuffer()
                                val frames = shorts.remaining() / outputChannels
                                val resampled = ByteArrayOutputStream()
                                for (frame in 0 until frames) {
                                    var sampleSum = 0
                                    for (channel in 0 until outputChannels) {
                                        sampleSum += shorts.get(
                                            frame * outputChannels + channel,
                                        ).toInt()
                                    }
                                    val monoValue = sampleSum / outputChannels
                                    resampleSum += monoValue
                                    resampleCount++
                                    resamplePhase += 1.0
                                    if (resamplePhase >= resampleStep) {
                                        val value = (resampleSum / resampleCount)
                                            .toInt()
                                            .coerceIn(-32768, 32767)
                                        resampled.write(value and 0xFF)
                                        resampled.write((value shr 8) and 0xFF)
                                        resampleSum = 0.0
                                        resampleCount = 0
                                        resamplePhase -= resampleStep
                                    }
                                }
                                val outputBytes = resampled.toByteArray()
                                stream.write(outputBytes)
                                totalBytes += outputBytes.size
                                if (totalBytes >= maxBytes) {
                                    outputDone = true
                                }
                            }
                            codec.releaseOutputBuffer(outputIndex, false)
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                                outputDone = true
                            }
                        }
                    }

                    if (resampleCount > 0) {
                        val value = (resampleSum / resampleCount)
                            .toInt()
                            .coerceIn(-32768, 32767)
                        stream.write(value and 0xFF)
                        stream.write((value shr 8) and 0xFF)
                        totalBytes += 2
                    }

                    val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
                    header.put("RIFF".toByteArray())
                    header.putInt(36 + totalBytes)
                    header.put("WAVE".toByteArray())
                    header.put("fmt ".toByteArray())
                    header.putInt(16)
                    header.putShort(1.toShort())
                    header.putShort(1.toShort())
                    header.putInt(targetRate)
                    header.putInt(targetRate * 2)
                    header.putShort(2.toShort())
                    header.putShort(16.toShort())
                    header.put("data".toByteArray())
                    header.putInt(totalBytes)
                    RandomAccessFile(output, "rw").use { raf ->
                        raf.seek(0)
                        raf.write(header.array())
                    }
                }

                runOnUiThread {
                    result.success(
                        mapOf(
                            "path" to output.absolutePath,
                            "sampleRate" to targetRate,
                            "duration" to fullDurationSeconds,
                        ),
                    )
                }
            } catch (error: Exception) {
                runOnUiThread { result.error("decode", error.message, null) }
            } finally {
                try {
                    codec?.stop()
                    codec?.release()
                } catch (_: Exception) {
                }
                try {
                    extractor?.release()
                } catch (_: Exception) {
                }
            }
        }.start()
    }
}
