package io.github.thisisankit27.dndreader

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.security.MessageDigest
import java.util.UUID

/**
 * Copies a document the system handed us (picker, ACTION_VIEW, ACTION_SEND) into app-private storage.
 *
 * Why a copy: the reader is built on `String path`, and an Android document is a `content://` URI that
 * may be a one-shot grant (Gmail, Drive) and cannot be opened by PDFium. `filesDir` (unlike the cache)
 * is never evicted by the system, so "reopen the last document" keeps working. The folder is named by the
 * SHA-256 of the bytes, so sharing the same attachment twice (a fresh URI each time) lands on the same
 * folder instead of adding a duplicate. No storage permission is involved.
 *
 * The document is untrusted input: only `content://` is accepted, the name is sanitised, and nothing
 * here looks inside the file.
 */
class DocumentImporter(context: Context) {
    class ImportException(val code: String, message: String, cause: Throwable? = null) :
        Exception(message, cause)

    data class Imported(val path: String, val name: String)

    private val resolver = context.contentResolver
    val root: File = File(context.filesDir, "documents")

    /** Blocking; call off the main thread. */
    fun import(uri: Uri): Imported {
        if (uri.scheme != "content") {
            throw ImportException("unsupported", "Only content:// documents are accepted")
        }
        root.mkdirs()
        sweepStaleTemporaries()
        val name = sanitizeName(displayName(uri))
        val tmp = File(root, "$TMP_PREFIX${UUID.randomUUID()}$TMP_SUFFIX")
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            val input = try {
                resolver.openInputStream(uri)
            } catch (e: SecurityException) {
                throw ImportException("denied", "Access to the document was revoked", e)
            } catch (e: FileNotFoundException) {
                throw ImportException("missing", "The document is no longer available", e)
            } ?: throw ImportException("missing", "The provider returned no data")
            var total = 0L
            input.use { src ->
                tmp.outputStream().use { dst ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = src.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_BYTES) {
                            throw ImportException("too_large", "The document exceeds $MAX_BYTES bytes")
                        }
                        digest.update(buffer, 0, read)
                        dst.write(buffer, 0, read)
                    }
                }
            }
            val key = digest.digest().joinToString("") { "%02x".format(it) }
            val dir = File(root, key)
            dir.mkdirs()
            // Same bytes: the latest display name wins, so the title is the one the user just saw.
            dir.listFiles()?.forEach { it.delete() }
            val dest = File(dir, name)
            if (!tmp.renameTo(dest)) throw ImportException("failed", "Could not store the document")
            dir.setLastModified(System.currentTimeMillis())
            return Imported(dest.path, name)
        } catch (e: ImportException) {
            throw e
        } catch (e: SecurityException) {
            throw ImportException("denied", "Access to the document was revoked", e)
        } catch (e: IOException) {
            val text = (e.message ?: "") + (e.cause?.message ?: "")
            if (text.contains("ENOSPC") || text.contains("No space left")) {
                throw ImportException("no_space", "Not enough free storage", e)
            }
            throw ImportException("failed", "Could not read the document", e)
        } finally {
            tmp.delete()
        }
    }

    private fun displayName(uri: Uri): String? = try {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }
    } catch (e: Exception) {
        null
    } ?: uri.lastPathSegment

    /** A temp file left by an import that was killed mid-copy. */
    private fun sweepStaleTemporaries() {
        val cutoff = System.currentTimeMillis() - 10 * 60 * 1000
        root.listFiles()?.forEach {
            if (it.isFile && it.name.startsWith(TMP_PREFIX) && it.name.endsWith(TMP_SUFFIX) &&
                it.lastModified() < cutoff
            ) it.delete()
        }
    }

    companion object {
        const val TMP_PREFIX = ".import-"
        const val TMP_SUFFIX = ".tmp"

        /** A reader's PDF; anything bigger is refused before it fills the phone. */
        const val MAX_BYTES = 1L shl 30

        private val FORBIDDEN = Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]")

        /** A file name that is safe as a single path segment and ends in .pdf. */
        fun sanitizeName(raw: String?): String {
            var name = (raw ?: "").replace(FORBIDDEN, "_").trim().trim('.', ' ')
            if (name.isEmpty()) return "document.pdf"
            if (!name.lowercase().endsWith(".pdf")) name += ".pdf"
            if (name.length > 120) name = name.take(116).trimEnd('.', ' ') + ".pdf"
            return name
        }
    }
}
