package ir.honarmardomi.tamasyar

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.ContactsContract

/** One contact per Android contact ID, including contacts without a telephone number. */
data class TamasContact(
    val id: Long,
    val name: String,
    val phones: List<String>,
    val starred: Boolean
) {
    val primaryNumber: String get() = phones.firstOrNull().orEmpty()
}

/**
 * Uses the same Android ContactsProvider as PayamYar. No cloud syncing,
 * duplicate copy of the address book, hardcoded limit or remote upload.
 * Call off the UI thread only; Android permission must be granted.
 */
object TamasContactRepository {
    fun load(context: Context): List<TamasContact> {
        if (context.checkSelfPermission(Manifest.permission.READ_CONTACTS) !=
            PackageManager.PERMISSION_GRANTED) return emptyList()
        data class MutableContact(
            val id: Long, val name: String, val starred: Boolean,
            val phones: LinkedHashMap<String, String> = linkedMapOf()
        )
        val people = linkedMapOf<Long, MutableContact>()
        val cr = context.contentResolver
        cr.query(
            ContactsContract.Contacts.CONTENT_URI,
            arrayOf(
                ContactsContract.Contacts._ID,
                ContactsContract.Contacts.DISPLAY_NAME_PRIMARY,
                ContactsContract.Contacts.STARRED
            ), null, null, ContactsContract.Contacts.DISPLAY_NAME_PRIMARY + " COLLATE LOCALIZED ASC"
        )?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow(ContactsContract.Contacts._ID)
            val name = cursor.getColumnIndexOrThrow(ContactsContract.Contacts.DISPLAY_NAME_PRIMARY)
            val starred = cursor.getColumnIndexOrThrow(ContactsContract.Contacts.STARRED)
            while (cursor.moveToNext()) {
                val key = cursor.getLong(id)
                people[key] = MutableContact(key, cursor.getString(name)
                    ?.trim().takeUnless { it.isNullOrBlank() } ?: "بدون نام",
                    cursor.getInt(starred) == 1)
            }
        }
        cr.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
            ), null, null, null
        )?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.CONTACT_ID)
            val number = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.NUMBER)
            val name = cursor.getColumnIndexOrThrow(ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)
            while (cursor.moveToNext()) {
                val key = cursor.getLong(id)
                val displayNumber = cursor.getString(number).orEmpty().trim()
                val norm = TamasPhone.normalize(displayNumber)
                if (norm.isBlank()) continue
                val person = people.getOrPut(key) {
                    MutableContact(key, cursor.getString(name).orEmpty().ifBlank { "بدون نام" }, false)
                }
                person.phones.putIfAbsent(norm, displayNumber)
            }
        }
        return people.values.map {
            TamasContact(it.id, it.name, it.phones.values.toList(), it.starred)
        }.sortedWith(compareBy<TamasContact> { it.name.lowercase() }.thenBy { it.id })
    }

    fun search(all: List<TamasContact>, typed: String, starsOnly: Boolean,
               starred: Set<String>, sortFavoritesFirst: Boolean): List<TamasContact> {
        val query = TamasPhone.ascii(typed).trim().lowercase()
        val normalizedQuery = TamasPhone.normalize(query)
        val filtered = all.filter { person ->
            val favorite = person.starred || person.phones.any {
                TamasPhone.normalize(it) in starred
            }
            (!starsOnly || favorite) &&
                (query.isBlank() || person.name.lowercase().contains(query) ||
                    person.phones.any { number ->
                        TamasPhone.ascii(number).contains(query) ||
                            TamasPhone.normalize(number).contains(normalizedQuery)
                    })
        }
        if (!sortFavoritesFirst) return filtered
        return filtered.sortedWith(
            compareByDescending<TamasContact> { person ->
                person.starred || person.phones.any {
                    TamasPhone.normalize(it) in starred
                }
            }.thenBy { it.name.lowercase() }
        )
    }
}
