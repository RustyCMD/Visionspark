package app.visionspark.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.content.ContentValues
import java.io.OutputStream // For writing to output stream
import java.io.IOException
import android.content.Intent // Added for Media Scan
import android.net.Uri // Added for Media Scan

class MainActivity : FlutterActivity() {
    private val MEDIA_CHANNEL = "com.visionspark.app/media"
    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL)

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImageToGallery" -> {
                    try {
                        val arguments = call.arguments as? Map<String, Any>
                        val imageBytes = arguments?.get("imageBytes") as? ByteArray
                        val filename = arguments?.get("filename") as? String ?: "VisionsparkImage.png"
                        val albumName = arguments?.get("albumName") as? String ?: "Visionspark"

                        if (imageBytes == null) {
                            Log.e("MainActivity", "Image bytes are null")
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        val resolver = applicationContext.contentResolver
                        val contentValues = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, filename)
                            put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DCIM + "/Camera")
                                put(MediaStore.MediaColumns.IS_PENDING, 1)
                            } else {
                                // For older versions, MediaStore handles default location (usually Pictures)
                            }
                        }

                        val imageUri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)

                        if (imageUri == null) {
                            Log.e("MainActivity", "Failed to create new MediaStore record.")
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        var outputStream: OutputStream? = null
                        try {
                            outputStream = resolver.openOutputStream(imageUri)
                            if (outputStream == null) {
                                throw IOException("Failed to get output stream.")
                            }
                            outputStream.write(imageBytes)
                            Log.d("MainActivity", "Image saved successfully to $imageUri")
                            
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                contentValues.clear()
                                contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                                resolver.update(imageUri, contentValues, null, null)
                            }
                            result.success(true)

                            // Explicitly trigger media scan
                            Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE).also { mediaScanIntent ->
                                mediaScanIntent.data = imageUri
                                applicationContext.sendBroadcast(mediaScanIntent)
                                Log.d("MainActivity", "Media scan broadcast sent for $imageUri")
                            }

                        } catch (e: Exception) {
                            Log.e("MainActivity", "Error saving image: ", e)
                            // Clean up if an error occurred during write
                            resolver.delete(imageUri, null, null)
                            result.success(false)
                        } finally {
                            outputStream?.close()
                        }
                    } catch (e: Exception) {
                        Log.e("MainActivity", "Error processing saveImageToGallery: ", e)
                        result.success(false)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
