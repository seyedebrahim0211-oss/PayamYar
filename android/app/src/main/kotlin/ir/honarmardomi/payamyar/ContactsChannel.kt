package ir.honarmardomi.payamyar

import android.Manifest
import android.app.Activity
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.ContactsContract
import android.provider.ContactsContract.CommonDataKinds.Email
import android.provider.ContactsContract.CommonDataKinds.Event
import android.provider.ContactsContract.CommonDataKinds.Note
import android.provider.ContactsContract.CommonDataKinds.Organization
import android.provider.ContactsContract.CommonDataKinds.Phone
import android.provider.ContactsContract.CommonDataKinds.Photo
import android.provider.ContactsContract.CommonDataKinds.StructuredName
import android.provider.OpenableColumns
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.xmlpull.v1.XmlPullParser
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/**
 * Phone-book manager for the PayamYar "Contacts" tab: read, add, edit, delete, star, join
 * duplicates, contact photos, file import/export (VCF, XLSX) through Android's own pickers.
 * Everything stays on the phone; nothing is uploaded.
 */
class ContactsChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "ir.honarmardomi.payamyar/contacts")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    companion object {
        const val REQ_PERMISSION = 2120
        const val REQ_PHOTO = 2121
        const val REQ_CREATE = 2122
        const val REQ_OPEN = 2123
    }

    init {
        channel.setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun has(p: String) = ContextCompat.checkSelfPermission(activity, p) == PackageManager.PERMISSION_GRANTED
    private val cr get() = activity.contentResolver

    private fun background(result: MethodChannel.Result, block: () -> Any?) = worker.execute {
        try {
            val value = block()
            main.post { result.success(value) }
        } catch (e: Exception) {
            main.post { result.error("CONTACTS", e.message ?: "عملیات مخاطبین انجام نشد.", null) }
        }
    }

    private fun startForResult(result: MethodChannel.Result, intent: Intent, code: Int) {
        pending?.success(null)
        pending = result
        try {
            activity.startActivityForResult(intent, code)
        } catch (e: Exception) {
            pending = null
            result.error("CONTACTS", "برنامه مناسب برای این کار روی گوشی پیدا نشد.", null)
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "permissions" -> result.success(mapOf("read" to has(Manifest.permission.READ_CONTACTS),
                "write" to has(Manifest.permission.WRITE_CONTACTS)))
            "requestPermissions" -> {
                if (has(Manifest.permission.READ_CONTACTS) && has(Manifest.permission.WRITE_CONTACTS)) {
                    result.success(true)
                } else {
                    pending?.success(null)
                    pending = result
                    ActivityCompat.requestPermissions(activity,
                        arrayOf(Manifest.permission.READ_CONTACTS, Manifest.permission.WRITE_CONTACTS), REQ_PERMISSION)
                }
            }
            "list" -> background(result) { list() }
            "photo" -> background(result) { photo(call.argument<Number>("id")?.toLong() ?: 0L) }
            "save" -> background(result) { save(call) }
            "delete" -> background(result) { delete(call.argument<List<Number>>("ids").orEmpty().map { it.toLong() }) }
            "star" -> background(result) {
                star(call.argument<Number>("id")?.toLong() ?: 0L, call.argument<Boolean>("value") ?: false)
            }
            "join" -> background(result) { join(call.argument<List<Number>>("ids").orEmpty().map { it.toLong() }) }
            "xlsxWrite" -> background(result) {
                Xlsx.write(call.argument<List<List<Any?>>>("rows").orEmpty().map { r -> r.map { it?.toString() ?: "" } })
            }
            "xlsxRead" -> background(result) { Xlsx.read(call.argument<ByteArray>("bytes") ?: ByteArray(0)) }
            "pickPhoto" -> startForResult(result,
                Intent(Intent.ACTION_GET_CONTENT).setType("image/*").addCategory(Intent.CATEGORY_OPENABLE), REQ_PHOTO)
            "saveFile" -> {
                pendingBytes = call.argument<ByteArray>("bytes")
                startForResult(result, Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                    .setType(call.argument<String>("mime") ?: "application/octet-stream")
                    .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "PayamYar"), REQ_CREATE)
            }
            "openFile" -> startForResult(result, Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
                .putExtra(Intent.EXTRA_MIME_TYPES, call.argument<List<String>>("mimes").orEmpty().toTypedArray()), REQ_OPEN)
            "importWithSystem" -> background(result) { importWithSystem(call.argument<ByteArray>("bytes") ?: ByteArray(0)) }
            "openSystemEditor" -> {
                try {
                    val uri = ContentUris.withAppendedId(ContactsContract.Contacts.CONTENT_URI, call.argument<Number>("id")?.toLong() ?: 0L)
                    activity.startActivity(Intent(Intent.ACTION_EDIT).setDataAndType(uri, ContactsContract.Contacts.CONTENT_ITEM_TYPE)
                        .putExtra("finishActivityOnSaveCompleted", true))
                    result.success(true)
                } catch (_: Exception) { result.success(false) }
            }
            "dial" -> {
                try {
                    activity.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(call.argument<String>("number").orEmpty()))))
                    result.success(true)
                } catch (_: Exception) { result.success(false) }
            }
            "email" -> {
                try {
                    activity.startActivity(Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:" + call.argument<String>("address").orEmpty())))
                    result.success(true)
                } catch (_: Exception) { result.success(false) }
            }
            else -> result.notImplemented()
        }
    }

    // ───────────── read ─────────────

    private fun list(): List<Map<String, Any?>> {
        check(has(Manifest.permission.READ_CONTACTS)) { "برای دیدن مخاطبین، اجازه دفترچه تلفن را بدهید." }
        val contacts = LinkedHashMap<Long, MutableMap<String, Any?>>()
        cr.query(ContactsContract.Contacts.CONTENT_URI,
            arrayOf(ContactsContract.Contacts._ID, ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
                ContactsContract.Contacts.STARRED, ContactsContract.Contacts.PHOTO_THUMBNAIL_URI,
                ContactsContract.Contacts.LOOKUP_KEY, ContactsContract.Contacts.CONTACT_LAST_UPDATED_TIMESTAMP),
            null, null, ContactsContract.Contacts.DISPLAY_NAME_PRIMARY + " COLLATE LOCALIZED ASC")?.use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                contacts[id] = mutableMapOf("id" to id, "name" to (c.getString(1) ?: ""), "starred" to (c.getInt(2) == 1),
                    "hasPhoto" to !c.getString(3).isNullOrBlank(), "lookup" to (c.getString(4) ?: ""),
                    "updated" to c.getLong(5), "phones" to mutableListOf<Map<String, Any?>>(),
                    "emails" to mutableListOf<Map<String, Any?>>(), "org" to "", "title" to "", "note" to "", "birthday" to "")
            }
        }
        val kinds = arrayOf(Phone.CONTENT_ITEM_TYPE, Email.CONTENT_ITEM_TYPE, Organization.CONTENT_ITEM_TYPE,
            Note.CONTENT_ITEM_TYPE, Event.CONTENT_ITEM_TYPE)
        cr.query(ContactsContract.Data.CONTENT_URI,
            arrayOf(ContactsContract.Data.CONTACT_ID, ContactsContract.Data.MIMETYPE, ContactsContract.Data.DATA1,
                ContactsContract.Data.DATA2, ContactsContract.Data.DATA3, ContactsContract.Data.DATA4),
            ContactsContract.Data.MIMETYPE + " IN (?,?,?,?,?)", kinds, null)?.use { c ->
            while (c.moveToNext()) {
                val row = contacts[c.getLong(0)] ?: continue
                val value = c.getString(2)?.trim().orEmpty()
                if (value.isEmpty()) continue
                when (c.getString(1)) {
                    Phone.CONTENT_ITEM_TYPE -> {
                        @Suppress("UNCHECKED_CAST") val list = row["phones"] as MutableList<Map<String, Any?>>
                        if (list.none { it["value"] == value }) list.add(mapOf("value" to value, "type" to c.getInt(3), "label" to (c.getString(4) ?: "")))
                    }
                    Email.CONTENT_ITEM_TYPE -> {
                        @Suppress("UNCHECKED_CAST") val list = row["emails"] as MutableList<Map<String, Any?>>
                        if (list.none { it["value"] == value }) list.add(mapOf("value" to value, "type" to c.getInt(3), "label" to (c.getString(4) ?: "")))
                    }
                    Organization.CONTENT_ITEM_TYPE -> { row["org"] = value; row["title"] = c.getString(5) ?: "" }
                    Note.CONTENT_ITEM_TYPE -> row["note"] = value
                    Event.CONTENT_ITEM_TYPE -> if (c.getInt(3) == Event.TYPE_BIRTHDAY) row["birthday"] = value
                }
            }
        }
        return contacts.values.toList()
    }

    private fun photo(id: Long): ByteArray? {
        if (!has(Manifest.permission.READ_CONTACTS) || id <= 0) return null
        val uri = ContentUris.withAppendedId(ContactsContract.Contacts.CONTENT_URI, id)
        return ContactsContract.Contacts.openContactPhotoInputStream(cr, uri, true)?.use { it.readBytes() }
    }

    // ───────────── write ─────────────

    private fun requireWrite() =
        check(has(Manifest.permission.WRITE_CONTACTS)) { "برای ویرایش مخاطبین، اجازه نوشتن در دفترچه تلفن را بدهید." }

    private fun rawIds(contactId: Long): List<Long> {
        val ids = mutableListOf<Long>()
        cr.query(ContactsContract.RawContacts.CONTENT_URI, arrayOf(ContactsContract.RawContacts._ID),
            ContactsContract.RawContacts.CONTACT_ID + "=? AND " + ContactsContract.RawContacts.DELETED + "=0",
            arrayOf(contactId.toString()), null)?.use { c -> while (c.moveToNext()) ids.add(c.getLong(0)) }
        return ids
    }

    @Suppress("UNCHECKED_CAST")
    private fun save(call: MethodCall): Long {
        requireWrite()
        val id = call.argument<Number>("id")?.toLong() ?: 0L
        val name = call.argument<String>("name")?.trim().orEmpty()
        val phones = call.argument<List<Map<String, Any?>>>("phones").orEmpty()
        val emails = call.argument<List<Map<String, Any?>>>("emails").orEmpty()
        val org = call.argument<String>("org")?.trim().orEmpty()
        val title = call.argument<String>("title")?.trim().orEmpty()
        val note = call.argument<String>("note")?.trim().orEmpty()
        val birthday = call.argument<String>("birthday")?.trim().orEmpty()
        val photo = call.argument<ByteArray>("photo")
        val removePhoto = call.argument<Boolean>("removePhoto") ?: false
        require(name.isNotEmpty() || phones.isNotEmpty() || emails.isNotEmpty()) { "نام یا شماره مخاطب را وارد کنید." }

        val ops = ArrayList<ContentProviderOperation>()
        var rawId = 0L
        val existingRaws = if (id > 0) rawIds(id) else emptyList()
        if (existingRaws.isEmpty()) {
            ops.add(ContentProviderOperation.newInsert(ContactsContract.RawContacts.CONTENT_URI)
                .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, null)
                .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, null).build())
        } else {
            rawId = existingRaws.first()
            // Replace the editable fields on every raw contact of this person, then write them once.
            val kinds = mutableListOf(StructuredName.CONTENT_ITEM_TYPE, Phone.CONTENT_ITEM_TYPE, Email.CONTENT_ITEM_TYPE,
                Organization.CONTENT_ITEM_TYPE, Note.CONTENT_ITEM_TYPE)
            if (birthday.isNotEmpty() || call.argument<Boolean>("clearBirthday") == true) kinds.add(Event.CONTENT_ITEM_TYPE)
            if (photo != null || removePhoto) kinds.add(Photo.CONTENT_ITEM_TYPE)
            for (raw in existingRaws) for (kind in kinds) {
                val selection = if (kind == Event.CONTENT_ITEM_TYPE)
                    ContactsContract.Data.RAW_CONTACT_ID + "=? AND " + ContactsContract.Data.MIMETYPE + "=? AND " + Event.TYPE + "=" + Event.TYPE_BIRTHDAY
                else ContactsContract.Data.RAW_CONTACT_ID + "=? AND " + ContactsContract.Data.MIMETYPE + "=?"
                ops.add(ContentProviderOperation.newDelete(ContactsContract.Data.CONTENT_URI)
                    .withSelection(selection, arrayOf(raw.toString(), kind)).build())
            }
        }
        fun data(kind: String): ContentProviderOperation.Builder {
            val b = ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
            if (rawId > 0) b.withValue(ContactsContract.Data.RAW_CONTACT_ID, rawId)
            else b.withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
            return b.withValue(ContactsContract.Data.MIMETYPE, kind)
        }
        if (name.isNotEmpty()) ops.add(data(StructuredName.CONTENT_ITEM_TYPE).withValue(StructuredName.DISPLAY_NAME, name).build())
        for (p in phones) {
            val v = p["value"]?.toString()?.trim().orEmpty()
            if (v.isEmpty()) continue
            val type = (p["type"] as? Number)?.toInt() ?: Phone.TYPE_MOBILE
            val b = data(Phone.CONTENT_ITEM_TYPE).withValue(Phone.NUMBER, v).withValue(Phone.TYPE, type)
            if (type == Phone.TYPE_CUSTOM) b.withValue(Phone.LABEL, p["label"]?.toString().orEmpty())
            ops.add(b.build())
        }
        for (e in emails) {
            val v = e["value"]?.toString()?.trim().orEmpty()
            if (v.isEmpty()) continue
            ops.add(data(Email.CONTENT_ITEM_TYPE).withValue(Email.ADDRESS, v)
                .withValue(Email.TYPE, (e["type"] as? Number)?.toInt() ?: Email.TYPE_HOME).build())
        }
        if (org.isNotEmpty() || title.isNotEmpty())
            ops.add(data(Organization.CONTENT_ITEM_TYPE).withValue(Organization.COMPANY, org).withValue(Organization.TITLE, title).build())
        if (note.isNotEmpty()) ops.add(data(Note.CONTENT_ITEM_TYPE).withValue(Note.NOTE, note).build())
        if (birthday.isNotEmpty())
            ops.add(data(Event.CONTENT_ITEM_TYPE).withValue(Event.START_DATE, birthday).withValue(Event.TYPE, Event.TYPE_BIRTHDAY).build())
        if (photo != null) ops.add(data(Photo.CONTENT_ITEM_TYPE).withValue(Photo.PHOTO, shrink(photo, 720)).build())

        val results = cr.applyBatch(ContactsContract.AUTHORITY, ops)
        if (rawId == 0L) rawId = results.firstOrNull()?.uri?.let { ContentUris.parseId(it) } ?: 0L
        var contactId = id
        cr.query(ContentUris.withAppendedId(ContactsContract.RawContacts.CONTENT_URI, rawId),
            arrayOf(ContactsContract.RawContacts.CONTACT_ID), null, null, null)?.use { c ->
            if (c.moveToFirst()) contactId = c.getLong(0)
        }
        return contactId
    }

    private fun delete(ids: List<Long>): Int {
        requireWrite()
        var count = 0
        for (id in ids) {
            count += cr.delete(ContentUris.withAppendedId(ContactsContract.Contacts.CONTENT_URI, id), null, null)
        }
        return count
    }

    private fun star(id: Long, value: Boolean): Boolean {
        requireWrite()
        val values = android.content.ContentValues().apply { put(ContactsContract.Contacts.STARRED, if (value) 1 else 0) }
        return cr.update(ContentUris.withAppendedId(ContactsContract.Contacts.CONTENT_URI, id), values, null, null) > 0
    }

    /** Merges duplicates the Android way: their raw contacts are kept together as one person. */
    private fun join(ids: List<Long>): Boolean {
        requireWrite()
        require(ids.size >= 2) { "برای ادغام دست‌کم دو مخاطب لازم است." }
        val raws = ids.flatMap { rawIds(it) }.distinct()
        if (raws.size < 2) return false
        val ops = ArrayList<ContentProviderOperation>()
        val first = raws.first()
        for (other in raws.drop(1)) {
            ops.add(ContentProviderOperation.newUpdate(ContactsContract.AggregationExceptions.CONTENT_URI)
                .withValue(ContactsContract.AggregationExceptions.TYPE, ContactsContract.AggregationExceptions.TYPE_KEEP_TOGETHER)
                .withValue(ContactsContract.AggregationExceptions.RAW_CONTACT_ID1, first)
                .withValue(ContactsContract.AggregationExceptions.RAW_CONTACT_ID2, other).build())
        }
        cr.applyBatch(ContactsContract.AUTHORITY, ops)
        return true
    }

    private fun shrink(bytes: ByteArray, max: Int): ByteArray {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= max && bounds.outHeight / (sample * 2) >= max) sample *= 2
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return bytes
        val scale = minOf(1f, max.toFloat() / maxOf(bitmap.width, bitmap.height))
        val out = if (scale < 1f) Bitmap.createScaledBitmap(bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true) else bitmap
        return ByteArrayOutputStream().use { s -> out.compress(Bitmap.CompressFormat.JPEG, 88, s); s.toByteArray() }
    }

    /** Hands a VCF file to the phone's own Contacts app, which imports it with its usual screen. */
    private fun importWithSystem(bytes: ByteArray): Boolean {
        require(bytes.isNotEmpty()) { "فایل خالی است." }
        val dir = File(activity.cacheDir, "updates").apply { mkdirs() }
        val file = File(dir, "payamyar-import.vcf")
        file.writeBytes(bytes)
        val uri = FileProvider.getUriForFile(activity, activity.packageName + ".updates", file)
        main.post {
            try {
                activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "text/x-vcard")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
            } catch (_: Exception) { }
        }
        return true
    }

    // ───────────── activity results ─────────────

    fun onPermissionResult(requestCode: Int) {
        if (requestCode != REQ_PERMISSION) return
        val r = pending ?: return
        pending = null
        r.success(has(Manifest.permission.READ_CONTACTS) && has(Manifest.permission.WRITE_CONTACTS))
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode !in REQ_PHOTO..REQ_OPEN) return false
        val r = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { r.success(null); pendingBytes = null; return true }
        worker.execute {
            try {
                val value: Any? = when (requestCode) {
                    REQ_PHOTO -> cr.openInputStream(uri)?.use { it.readBytes() }?.let { shrink(it, 720) }
                    REQ_CREATE -> {
                        val bytes = pendingBytes ?: ByteArray(0)
                        cr.openOutputStream(uri, "wt")?.use { it.write(bytes) }
                        true
                    }
                    else -> {
                        var name = ""
                        cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) name = c.getString(0) ?: "" }
                        val bytes = cr.openInputStream(uri)?.use { it.readBytes() } ?: ByteArray(0)
                        check(bytes.size <= 20 * 1024 * 1024) { "حجم فایل بیش از ۲۰ مگابایت است." }
                        mapOf("name" to name, "bytes" to bytes)
                    }
                }
                main.post { r.success(value) }
            } catch (e: Exception) {
                main.post { r.error("CONTACTS", e.message ?: "خواندن یا نوشتن فایل انجام نشد.", null) }
            } finally { pendingBytes = null }
        }
        return true
    }
}

/** Minimal, dependency-free Excel (.xlsx) writer/reader for one sheet of text cells. */
object Xlsx {
    private fun col(i: Int): String {
        var n = i + 1
        val sb = StringBuilder()
        while (n > 0) { val m = (n - 1) % 26; sb.insert(0, ('A' + m)); n = (n - 1) / 26 }
        return sb.toString()
    }

    private fun esc(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
        .filter { it == '\t' || it == '\n' || it == '\r' || it >= ' ' }

    fun write(rows: List<List<String>>): ByteArray {
        val sheet = StringBuilder()
        sheet.append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>")
            .append("<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">")
            .append("<sheetViews><sheetView workbookViewId=\"0\" rightToLeft=\"1\"><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>")
            .append("<cols>")
        val width = rows.maxOfOrNull { it.size } ?: 0
        for (c in 0 until width) sheet.append("<col min=\"").append(c + 1).append("\" max=\"").append(c + 1).append("\" width=\"22\" customWidth=\"1\"/>")
        sheet.append("</cols><sheetData>")
        rows.forEachIndexed { r, row ->
            sheet.append("<row r=\"").append(r + 1).append("\">")
            row.forEachIndexed { c, v ->
                if (v.isNotEmpty()) {
                    sheet.append("<c r=\"").append(col(c)).append(r + 1).append("\" t=\"inlineStr\"")
                    if (r == 0) sheet.append(" s=\"1\"")
                    sheet.append("><is><t xml:space=\"preserve\">").append(esc(v)).append("</t></is></c>")
                }
            }
            sheet.append("</row>")
        }
        sheet.append("</sheetData></worksheet>")
        val files = linkedMapOf(
            "[Content_Types].xml" to "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/></Types>",
            "_rels/.rels" to "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>",
            "xl/workbook.xml" to "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Contacts\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>",
            "xl/_rels/workbook.xml.rels" to "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>",
            "xl/styles.xml" to "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Tahoma\"/></font><font><b/><sz val=\"11\"/><color rgb=\"FFFFFFFF\"/><name val=\"Tahoma\"/></font></fonts><fills count=\"3\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill><fill><patternFill patternType=\"solid\"><fgColor rgb=\"FF087F81\"/><bgColor indexed=\"64\"/></patternFill></fill></fills><borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"2\" borderId=\"0\" xfId=\"0\" applyFont=\"1\" applyFill=\"1\"/></cellXfs></styleSheet>",
            "xl/worksheets/sheet1.xml" to sheet.toString(),
        )
        return ByteArrayOutputStream().use { out ->
            ZipOutputStream(out).use { zip ->
                for ((name, text) in files) {
                    zip.putNextEntry(ZipEntry(name)); zip.write(text.toByteArray(Charsets.UTF_8)); zip.closeEntry()
                }
            }
            out.toByteArray()
        }
    }

    private fun colIndex(ref: String): Int {
        var n = 0
        for (ch in ref) { if (ch !in 'A'..'Z') break; n = n * 26 + (ch - 'A' + 1) }
        return n - 1
    }

    /** First worksheet as rows of text; shared strings, inline strings and numbers are supported. */
    fun read(bytes: ByteArray): List<List<String>> {
        val entries = HashMap<String, ByteArray>()
        ZipInputStream(ByteArrayInputStream(bytes)).use { zip ->
            var e = zip.nextEntry
            while (e != null) {
                if (e.name == "xl/sharedStrings.xml" || e.name.startsWith("xl/worksheets/sheet")) entries[e.name] = zip.readBytes()
                e = zip.nextEntry
            }
        }
        require(entries.isNotEmpty()) { "این فایل اکسل (xlsx) معتبر نیست." }
        val shared = mutableListOf<String>()
        entries["xl/sharedStrings.xml"]?.let { data ->
            val p = android.util.Xml.newPullParser()
            p.setInput(ByteArrayInputStream(data), "UTF-8")
            var current: StringBuilder? = null
            var inT = false
            while (p.next() != XmlPullParser.END_DOCUMENT) {
                when (p.eventType) {
                    XmlPullParser.START_TAG -> when (p.name) { "si" -> current = StringBuilder(); "t" -> inT = true }
                    XmlPullParser.TEXT -> if (inT) current?.append(p.text)
                    XmlPullParser.END_TAG -> when (p.name) { "t" -> inT = false; "si" -> { shared.add(current?.toString() ?: ""); current = null } }
                }
            }
        }
        val sheetKey = if (entries.containsKey("xl/worksheets/sheet1.xml")) "xl/worksheets/sheet1.xml"
            else entries.keys.filter { it.startsWith("xl/worksheets/sheet") }.sorted().firstOrNull() ?: return emptyList()
        val rows = mutableListOf<List<String>>()
        val p = android.util.Xml.newPullParser()
        p.setInput(ByteArrayInputStream(entries.getValue(sheetKey)), "UTF-8")
        var row: MutableMap<Int, String>? = null
        var cellCol = 0
        var cellType = ""
        val text = StringBuilder()
        var inValue = false
        var nextCol = 0
        while (p.next() != XmlPullParser.END_DOCUMENT) {
            when (p.eventType) {
                XmlPullParser.START_TAG -> when (p.name) {
                    "row" -> { row = HashMap(); nextCol = 0 }
                    "c" -> {
                        val ref = p.getAttributeValue(null, "r")
                        cellCol = if (ref != null) colIndex(ref) else nextCol
                        nextCol = cellCol + 1
                        cellType = p.getAttributeValue(null, "t") ?: ""
                        text.setLength(0)
                    }
                    "v", "t" -> inValue = true
                }
                XmlPullParser.TEXT -> if (inValue) text.append(p.text)
                XmlPullParser.END_TAG -> when (p.name) {
                    "v", "t" -> inValue = false
                    "c" -> {
                        val raw = text.toString()
                        val value = when (cellType) {
                            "s" -> shared.getOrNull(raw.trim().toIntOrNull() ?: -1) ?: ""
                            "b" -> if (raw == "1") "TRUE" else "FALSE"
                            else -> if (cellType.isEmpty() && raw.endsWith(".0")) raw.dropLast(2) else raw
                        }
                        row?.put(cellCol, value)
                    }
                    "row" -> {
                        val r = row ?: HashMap()
                        val max = r.keys.maxOrNull() ?: -1
                        rows.add((0..max).map { r[it] ?: "" })
                        row = null
                    }
                }
            }
        }
        return rows
    }
}
