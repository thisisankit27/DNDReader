package io.github.thisisankit27.dndreader

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * DEBUG BUILDS ONLY (lives in src/debug; absent from release and profile). Serves files pushed to
 * `files/testdocs/` as content:// URIs so intents can be driven from `adb shell am start` without a
 * second app, and fakes the failures a real provider produces:
 *   denied*.pdf -> SecurityException (permission revoked)   gone*.pdf -> FileNotFoundException
 *   slow*.pdf   -> 3 s before the data is available (a cloud file that must download first)
 * Exported with no permission because it exists only so a developer's shell can read test fixtures.
 */
class TestDocsProvider : ContentProvider() {
    override fun onCreate() = true

    private fun fileFor(uri: Uri): File =
        File(File(context!!.filesDir, "testdocs"), uri.lastPathSegment ?: "")

    override fun getType(uri: Uri) = "application/pdf"

    override fun query(
        uri: Uri, projection: Array<out String>?, selection: String?,
        selectionArgs: Array<out String>?, sortOrder: String?,
    ): Cursor {
        val cursor = MatrixCursor(arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE))
        val f = fileFor(uri)
        cursor.addRow(arrayOf<Any>(uri.getQueryParameter("name") ?: f.name, f.length()))
        return cursor
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val name = uri.lastPathSegment ?: ""
        if (name.startsWith("denied")) throw SecurityException("revoked")
        if (name.startsWith("gone")) throw FileNotFoundException("gone")
        if (name.startsWith("slow")) Thread.sleep(3000)
        val f = fileFor(uri)
        if (!f.exists()) throw FileNotFoundException(name)
        return ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, v: ContentValues?, s: String?, a: Array<out String>?) = 0
}
