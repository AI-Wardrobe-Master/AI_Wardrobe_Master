package com.example.ai_wardrobe_app

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val downloadChannel = "ai_wardrobe_app/downloads"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveImageToGallery" && call.method != "saveImageToDownloads") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val bytes = call.argument<ByteArray>("bytes")
                val fileName = call.argument<String>("fileName")

                if (bytes == null || fileName.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "Missing bytes or file name.", null)
                    return@setMethodCallHandler
                }

                try {
                    result.success(saveImageToGallery(bytes, fileName))
                } catch (exception: Exception) {
                    result.error("SAVE_FAILED", exception.message, null)
                }
            }
    }

    private fun saveImageToGallery(bytes: ByteArray, fileName: String): String {
        val resolver = applicationContext.contentResolver
        val collection =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            } else {
                MediaStore.Files.getContentUri("external")
            }

        val values =
            ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        "${Environment.DIRECTORY_PICTURES}/AIWardrobe",
                    )
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }

        val uri =
            resolver.insert(collection, values)
                ?: throw IllegalStateException("Unable to create a Gallery entry.")

        resolver.openOutputStream(uri)?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: throw IllegalStateException("Unable to open the Gallery output stream.")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        }

        return uri.toString()
    }
}
