package com.snipfit.app

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Hosts Snipfit's own platform channels. Heavy work (encoding, segmentation)
 * runs on background executors; results are posted back on the main thread.
 */
class MainActivity : FlutterActivity() {
    private val videoExecutor = Executors.newSingleThreadExecutor()
    private val visionExecutor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var encoder: VideoEncoder? = null
    private var tapSegmenter: TapSegmenter? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Backups are disabled in the manifest; nothing to do per path.
        MethodChannel(messenger, "snipfit/platform").setMethodCallHandler { call, result ->
            when (call.method) {
                "excludeFromBackup" -> result.success(null)
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "snipfit/video").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> videoExecutor.execute {
                    val ok = try {
                        encoder?.cancel()
                        encoder = VideoEncoder().also {
                            it.start(
                                call.argument<String>("path")!!,
                                call.argument<Int>("width")!!,
                                call.argument<Int>("height")!!,
                                call.argument<Int>("fps")!!,
                                call.argument<Int>("bitrate") ?: 6_000_000,
                            )
                        }
                        true
                    } catch (e: Exception) {
                        encoder = null
                        false
                    }
                    main.post { result.success(ok) }
                }
                "addFrame" -> {
                    val rgba = call.argument<ByteArray>("rgba")!!
                    videoExecutor.execute {
                        try {
                            encoder!!.addFrame(rgba)
                            main.post { result.success(null) }
                        } catch (e: Exception) {
                            main.post { result.error("encode_failed", e.message, null) }
                        }
                    }
                }
                "finish" -> videoExecutor.execute {
                    val ok = try {
                        encoder?.finish() ?: false
                    } catch (e: Exception) {
                        false
                    }
                    encoder = null
                    main.post { result.success(ok) }
                }
                "cancel" -> videoExecutor.execute {
                    encoder?.cancel()
                    encoder = null
                    main.post { result.success(null) }
                }
                else -> result.notImplemented()
            }
        }

        val share = ShareTargets(this)
        MethodChannel(messenger, "snipfit/share").setMethodCallHandler { call, result ->
            when (call.method) {
                "isInstalled" -> result.success(share.isInstalled(call.argument<String>("target")!!))
                "shareTo" -> result.success(
                    share.shareTo(
                        target = call.argument<String>("target")!!,
                        path = call.argument<String>("path")!!,
                        mimeType = call.argument<String>("mimeType")!!,
                        appIds = call.argument<Map<String, String>>("appIds") ?: emptyMap(),
                        caption = call.argument<String>("caption"),
                    ),
                )
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "snipfit/tap_segmenter").setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(TapSegmenter.isSupported(this))
                "segment" -> visionExecutor.execute {
                    try {
                        val seg = tapSegmenter ?: TapSegmenter(this).also { tapSegmenter = it }
                        val png = seg.segment(
                            call.argument<String>("path")!!,
                            call.argument<Double>("x")!!.toFloat(),
                            call.argument<Double>("y")!!.toFloat(),
                        )
                        main.post { result.success(png) }
                    } catch (e: Exception) {
                        main.post { result.error("segment_failed", e.message, null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        tapSegmenter?.close()
        encoder?.cancel()
        videoExecutor.shutdown()
        visionExecutor.shutdown()
        super.onDestroy()
    }
}
