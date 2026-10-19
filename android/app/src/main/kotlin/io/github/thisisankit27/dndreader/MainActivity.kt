package io.github.thisisankit27.dndreader

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Document access (channel `dndreader/documents`): the system picker, and ACTION_VIEW / ACTION_SEND
 * intents (cold start, warm start, and a second intent while a document is open). Every document is
 * copied into app-private storage by [DocumentImporter]; Dart only ever sees a file path.
 */
class MainActivity : FlutterActivity() {
    private lateinit var importer: DocumentImporter
    private var channel: MethodChannel? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    /** The launch intent was already handled (or belongs to a previous life of this activity). */
    private var launchIntentConsumed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A re-created activity (process death, "Don't keep activities") is handed the ORIGINAL launch
        // intent again. The document it named is restored from the saved document/page, so re-importing
        // it would reset the reader to page 1.
        launchIntentConsumed = savedInstanceState != null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        importer = DocumentImporter(applicationContext)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> startPick(result)
                "initialDocument" -> {
                    val uri = if (launchIntentConsumed) null else documentUri(intent)
                    launchIntentConsumed = true
                    if (uri == null) result.success(null) else importAsync(uri, result)
                }
                "documentsDir" -> result.success(importer.root.path)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val uri = documentUri(intent) ?: return
        setIntent(intent)
        importAsync(uri, object : MethodChannel.Result {
            override fun success(result: Any?) {
                channel?.invokeMethod("incoming", result)
            }

            override fun error(code: String, message: String?, details: Any?) {
                channel?.invokeMethod("incoming", mapOf("error" to code))
            }

            override fun notImplemented() {}
        })
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_PICK) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) result.success(null) else importAsync(uri, result)
    }

    private fun startPick(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("busy", "A picker is already open", null)
            return
        }
        val picker = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
        }
        pendingPick = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(picker, REQUEST_PICK)
        } catch (e: ActivityNotFoundException) {
            pendingPick = null
            result.error("unavailable", "No document picker is available", null)
        }
    }

    /** The document an ACTION_VIEW / ACTION_SEND intent names, or null. Untrusted: scheme is checked later. */
    private fun documentUri(intent: Intent?): Uri? {
        intent ?: return null
        return when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> {
                val stream: Uri? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
                stream ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
            }
            else -> null
        }
    }

    private fun importAsync(uri: Uri, result: MethodChannel.Result) {
        worker.execute {
            try {
                val imported = importer.import(uri)
                main.post { result.success(mapOf("path" to imported.path, "name" to imported.name)) }
            } catch (e: DocumentImporter.ImportException) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("failed", e.message, null) }
            }
        }
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }

    companion object {
        const val CHANNEL = "dndreader/documents"
        const val REQUEST_PICK = 4101
    }
}
