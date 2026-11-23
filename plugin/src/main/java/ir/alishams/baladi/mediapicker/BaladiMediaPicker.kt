package ir.alishams.baladi.mediapicker

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File
import java.io.FileOutputStream
import kotlin.math.roundToInt

class BaladiMediaPicker(godot: Godot) : GodotPlugin(godot) {
    override fun getPluginName(): String = BuildConfig.GODOT_PLUGIN_NAME

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("image_picked", String::class.java),
        SignalInfo("picker_cancelled"),
        SignalInfo("picker_error", String::class.java)
    )

    @UsedByGodot
    fun pickImage() {
        runOnHostThread {
            val host = activity
            if (host == null) {
                emitSignal("picker_error", "پنجره انتخاب تصویر در دسترس نیست.")
                return@runOnHostThread
            }
            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            try {
                host.startActivityForResult(intent, REQUEST_PICK_IMAGE)
            } catch (error: Exception) {
                emitSignal("picker_error", error.message ?: "بازکردن گالری ناموفق بود.")
            }
        }
    }

    override fun onMainActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_PICK_IMAGE) return
        if (resultCode != Activity.RESULT_OK) {
            emitSignal("picker_cancelled")
            return
        }
        val uri: Uri = data?.data ?: run {
            emitSignal("picker_cancelled")
            return
        }
        val host = activity ?: run {
            emitSignal("picker_error", "دسترسی به فایل انتخاب‌شده ممکن نیست.")
            return
        }

        try {
            val bitmap = decodeImage(host.contentResolver, uri)
            val file = File(host.cacheDir, "baladi_avatar_${System.currentTimeMillis()}.jpg")
            FileOutputStream(file).use { output ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, 92, output)) {
                    throw IllegalStateException("فشرده‌سازی تصویر ناموفق بود.")
                }
            }
            bitmap.recycle()
            emitSignal("image_picked", file.absolutePath)
        } catch (error: Exception) {
            emitSignal("picker_error", error.message ?: "خواندن تصویر انتخاب‌شده ناموفق بود.")
        }
    }

    private fun decodeImage(resolver: android.content.ContentResolver, uri: Uri): Bitmap {
        if (Build.VERSION.SDK_INT >= 28) {
            val source = ImageDecoder.createSource(resolver, uri)
            return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val maxSide = maxOf(info.size.width, info.size.height)
                if (maxSide > MAX_IMAGE_SIDE) {
                    val ratio = MAX_IMAGE_SIDE.toDouble() / maxSide.toDouble()
                    decoder.setTargetSize(
                        (info.size.width * ratio).roundToInt().coerceAtLeast(1),
                        (info.size.height * ratio).roundToInt().coerceAtLeast(1)
                    )
                }
            }
        }

        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        val boundsStream = resolver.openInputStream(uri)
            ?: throw IllegalArgumentException("فایل تصویر قابل خواندن نیست.")
        boundsStream.use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
            throw IllegalArgumentException("ابعاد تصویر قابل تشخیص نیست.")
        }
        var sample = 1
        while (maxOf(bounds.outWidth / sample, bounds.outHeight / sample) > MAX_IMAGE_SIDE) {
            sample *= 2
        }
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return resolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
            ?: throw IllegalArgumentException("رمزگشایی تصویر ناموفق بود.")
    }

    private companion object {
        const val REQUEST_PICK_IMAGE = 0xBA14
        const val MAX_IMAGE_SIDE = 2048
    }
}
