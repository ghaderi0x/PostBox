package com.uniqueone.postbox

import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hands text and JSON files shared to PostBox ("Share" and "Open with") to
 * Dart over a MethodChannel. Dart decides what the content is (cURL command,
 * Postman collection, PostBox export) and always shows a preview before
 * importing anything. Only plain text up to 5 MB is read.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result ->
            if (call.method == "getInitialShare") {
                result.success(pending)
                pending = null
            } else {
                result.notImplemented()
            }
        }
        channel = ch
        pending = extract(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val data = extract(intent) ?: return
        channel?.invokeMethod("onShare", data)
    }

    private fun extract(intent: Intent?): Map<String, String?>? {
        if (intent == null) return null
        when (intent.action) {
            Intent.ACTION_SEND -> {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                if (text != null) {
                    return mapOf(
                        "text" to text.take(MAX_BYTES),
                        "name" to intent.getStringExtra(Intent.EXTRA_SUBJECT),
                    )
                }
                val stream: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                return stream?.let { readUri(it) }
            }
            Intent.ACTION_VIEW -> {
                val uri = intent.data ?: return null
                // The OAuth redirect (com.uniqueone.postbox:/oauth2redirect) is
                // handled by app_links, not here.
                if (uri.scheme != "content" && uri.scheme != "file") return null
                return readUri(uri)
            }
        }
        return null
    }

    private fun readUri(uri: Uri): Map<String, String?>? {
        return try {
            contentResolver.openInputStream(uri)?.use { stream ->
                val buffer = ByteArray(MAX_BYTES + 1)
                var n = 0
                while (n < buffer.size) {
                    val r = stream.read(buffer, n, buffer.size - n)
                    if (r < 0) break
                    n += r
                }
                if (n > MAX_BYTES) null
                else mapOf("text" to String(buffer, 0, n, Charsets.UTF_8), "name" to uri.lastPathSegment)
            }
        } catch (e: Exception) {
            null
        }
    }

    companion object {
        private const val CHANNEL = "com.uniqueone.postbox/share"
        private const val MAX_BYTES = 5 * 1024 * 1024
    }
}
