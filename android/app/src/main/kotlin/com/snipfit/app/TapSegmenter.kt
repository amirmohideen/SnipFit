package com.snipfit.app

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.tasks.components.containers.NormalizedKeypoint
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.interactivesegmenter.InteractiveSegmenter
import java.io.ByteArrayOutputStream

/**
 * Tap-to-select garment using MediaPipe's Interactive Segmenter
 * (magic_touch.tflite, bundled in assets). Runs entirely on the device;
 * returns a grayscale PNG mask the same size as the photo.
 */
class TapSegmenter(context: Context) {
    private val segmenter: InteractiveSegmenter = InteractiveSegmenter.createFromOptions(
        context,
        InteractiveSegmenter.InteractiveSegmenterOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath("magic_touch.tflite").build())
            .setOutputCategoryMask(true)
            .setOutputConfidenceMasks(false)
            .build(),
    )

    fun segment(path: String, x: Float, y: Float): ByteArray? {
        val bitmap = loadUpright(path) ?: return null
        val roi = InteractiveSegmenter.RegionOfInterest.create(NormalizedKeypoint.create(x, y))
        val result = segmenter.segment(BitmapImageBuilder(bitmap).build(), roi)
        val maskImage = result.categoryMask().orElse(null) ?: return null
        val buffer = ByteBufferExtractor.extract(maskImage)
        val w = maskImage.width
        val h = maskImage.height
        val values = ByteArray(w * h)
        buffer.rewind()
        buffer.get(values, 0, minOf(values.size, buffer.remaining()))
        // The selected object is the region containing the tapped point.
        val tx = (x * (w - 1)).toInt().coerceIn(0, w - 1)
        val ty = (y * (h - 1)).toInt().coerceIn(0, h - 1)
        val selectedIsNonZero = values[ty * w + tx].toInt() != 0
        val pixels = IntArray(w * h)
        var count = 0
        for (i in values.indices) {
            val on = (values[i].toInt() != 0) == selectedIsNonZero
            if (on) count++
            val g = if (on) 255 else 0
            pixels[i] = Color.argb(255, g, g, g)
        }
        if (count < w * h / 400) return null
        val out = Bitmap.createBitmap(pixels, w, h, Bitmap.Config.ARGB_8888)
        val scaled = if (w != bitmap.width || h != bitmap.height) {
            Bitmap.createScaledBitmap(out, bitmap.width, bitmap.height, true)
        } else {
            out
        }
        val stream = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }

    private fun loadUpright(path: String): Bitmap? {
        val raw = BitmapFactory.decodeFile(path) ?: return null
        val degrees = when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
            ExifInterface.ORIENTATION_ROTATE_90 -> 90f
            ExifInterface.ORIENTATION_ROTATE_180 -> 180f
            ExifInterface.ORIENTATION_ROTATE_270 -> 270f
            else -> 0f
        }
        if (degrees == 0f) return raw
        return Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, Matrix().apply { postRotate(degrees) }, true)
    }

    fun close() = segmenter.close()

    companion object {
        /** Hide tap-to-select on very low-memory devices; gallery stays. */
        fun isSupported(context: Context): Boolean {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val info = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
            return !am.isLowRamDevice && info.totalMem >= 3L * 1024 * 1024 * 1024
        }
    }
}
