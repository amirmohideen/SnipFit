package com.snipfit.app

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File

/**
 * H.264 MP4 encoder for the reveal video. Takes RGBA frames from Dart,
 * converts them to YUV 4:2:0 and feeds the hardware encoder. The MP4 carries
 * no location or device metadata.
 */
class VideoEncoder {
    private var codec: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var track = -1
    private var muxerStarted = false
    private var width = 0
    private var height = 0
    private var fps = 30
    private var frameIndex = 0L
    private var outputPath: String? = null
    private val info = MediaCodec.BufferInfo()

    fun start(path: String, width: Int, height: Int, fps: Int, bitrate: Int) {
        this.width = width
        this.height = height
        this.fps = fps
        this.outputPath = path
        File(path).parentFile?.mkdirs()
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
            configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            start()
        }
        muxer = MediaMuxer(path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        frameIndex = 0
    }

    fun addFrame(rgba: ByteArray) {
        val c = codec ?: error("encoder not started")
        var index: Int
        do {
            index = c.dequeueInputBuffer(10_000)
            if (index < 0) drain(false)
        } while (index < 0)
        val image = c.getInputImage(index) ?: error("no input image")
        val planes = image.planes
        val y = planes[0].buffer
        val u = planes[1].buffer
        val v = planes[2].buffer
        val yRow = planes[0].rowStride
        val yPix = planes[0].pixelStride
        val uRow = planes[1].rowStride
        val uPix = planes[1].pixelStride
        val vRow = planes[2].rowStride
        val vPix = planes[2].pixelStride
        for (j in 0 until height) {
            for (i in 0 until width) {
                val p = (j * width + i) * 4
                val r = rgba[p].toInt() and 0xFF
                val g = rgba[p + 1].toInt() and 0xFF
                val b = rgba[p + 2].toInt() and 0xFF
                y.put(j * yRow + i * yPix, (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte())
                if ((j and 1) == 0 && (i and 1) == 0) {
                    val cu = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                    val cv = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                    u.put((j / 2) * uRow + (i / 2) * uPix, cu.coerceIn(0, 255).toByte())
                    v.put((j / 2) * vRow + (i / 2) * vPix, cv.coerceIn(0, 255).toByte())
                }
            }
        }
        val pts = frameIndex * 1_000_000L / fps
        c.queueInputBuffer(index, 0, width * height * 3 / 2, pts, 0)
        frameIndex++
        drain(false)
    }

    fun finish(): Boolean {
        val c = codec ?: return false
        var index: Int
        do {
            index = c.dequeueInputBuffer(10_000)
            if (index < 0) drain(false)
        } while (index < 0)
        c.queueInputBuffer(index, 0, 0, frameIndex * 1_000_000L / fps, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        drain(true)
        release()
        return muxerStarted
    }

    fun cancel() {
        try {
            release()
        } catch (_: Exception) {
        }
        outputPath?.let { File(it).delete() }
    }

    private fun drain(endOfStream: Boolean) {
        val c = codec ?: return
        val m = muxer ?: return
        while (true) {
            val index = c.dequeueOutputBuffer(info, 10_000)
            when {
                index == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!endOfStream) return
                index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    track = m.addTrack(c.outputFormat)
                    m.start()
                    muxerStarted = true
                }
                index >= 0 -> {
                    val buffer = c.getOutputBuffer(index)!!
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                    if (info.size > 0 && muxerStarted) {
                        buffer.position(info.offset)
                        buffer.limit(info.offset + info.size)
                        m.writeSampleData(track, buffer, info)
                    }
                    c.releaseOutputBuffer(index, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                }
            }
        }
    }

    private fun release() {
        codec?.let {
            try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        codec = null
        muxer?.let {
            if (muxerStarted) try { it.stop() } catch (_: Exception) {}
            it.release()
        }
        muxer = null
    }
}
