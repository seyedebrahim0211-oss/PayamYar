package ir.honarmardomi.tamasyar

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.widget.Toast
import android.app.role.RoleManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentUris
import android.content.Context
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.CallLog
import android.provider.ContactsContract
import android.telecom.TelecomManager
import android.telecom.PhoneAccountHandle
import android.content.ContentValues
import android.text.TextWatcher
import android.text.Editable
import android.view.Gravity
import android.view.View
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.ScrollView
import android.widget.TextView
import android.text.InputType
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : Activity() {
    private val prefs by lazy { TamasPreferences(this) }
    private val ink get() = if (prefs.dark) Color.WHITE else TamasStyle.ink
    private val paper get() = if (prefs.dark) Color.rgb(14, 27, 31) else TamasStyle.paper
    private val surface get() = if (prefs.dark) Color.rgb(26, 46, 51) else Color.WHITE
    private val gold get() = if (prefs.dark) TamasStyle.goldLight else TamasStyle.gold
    private val muted get() = if (prefs.dark) Color.rgb(174, 200, 194) else TamasStyle.muted
    private val requestedPermissions = mutableSetOf<String>()
    private var tab = 1
    private var digits = ""
    private var filter = ""
    private var pendingNumber: String? = null
    private var historyFilter = 0
    private var favoriteOnly = false
    private var contactsCache: List<TamasContact>? = null
    private var contactsListEpoch = 0
    private var renderEpoch = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = TamasStyle.tealDeep
        window.navigationBarColor = paper
        window.decorView.systemUiVisibility =
            if (prefs.dark) 0 else View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        intent?.data?.takeIf { it.scheme == "tel" }?.let {
            digits = it.schemeSpecificPart.orEmpty()
        }
        if (intent?.getBooleanExtra("open_updates", false) == true) tab = 3
        showTab()
        if (intent?.getBooleanExtra("open_updates", false) == true) checkForUpdates()
        TamasUpdateWorker.configure(this)
        TamasUpdater.check(this, automatic = true) { _, _ -> }
    }

    override fun onResume() {
        super.onResume()
        TamasUpdater.resumePendingInstall(this)
        TamasUpdater.check(this, automatic = true) { _, _ -> }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.data?.takeIf { it.scheme == "tel" }?.let {
            digits = it.schemeSpecificPart.orEmpty()
            tab = 1
            showTab()
        }
        if (intent.getBooleanExtra("open_updates", false)) {
            tab = 3
            showTab()
            checkForUpdates()
        }
    }

    private fun shape(color: Int, radius: Float = 18f): GradientDrawable =
        TamasStyle.panel(this, color, radius.toInt(), if (prefs.dark) Color.rgb(49, 75, 77) else TamasStyle.line)

    private fun dp(value: Int): Int = (resources.displayMetrics.density * value).toInt()
    private fun text(value: String, size: Float = 16f, bold: Boolean = false, color: Int = ink): TextView =
        TextView(this).apply {
            this.text = value
            textSize = size * prefs.scale()
            setTextColor(color)
            TamasStyle.apply(this, this@MainActivity, bold)
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(8), dp(8), dp(8), dp(8))
            textDirection = View.TEXT_DIRECTION_FIRST_STRONG
        }

    private fun action(value: String, filled: Boolean = false, click: () -> Unit): TextView =
        text(value, 15f, true, if (filled) Color.WHITE else ink).apply {
            gravity = Gravity.CENTER
            background = shape(if (filled) TamasStyle.teal else if (prefs.dark) Color.rgb(35, 60, 66) else TamasStyle.mist)
            setPadding(dp(10), dp(13), dp(10), dp(13))
            setOnClickListener { click() }
        }

    private fun vbox(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        layoutDirection = View.LAYOUT_DIRECTION_RTL
    }

    private fun hbox(): LinearLayout = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        layoutDirection = View.LAYOUT_DIRECTION_RTL
    }

    private fun addGap(container: LinearLayout, amount: Int = 8) {
        container.addView(View(this), LinearLayout.LayoutParams(1, dp(amount)))
    }

    private fun section(title: String, subtitle: String? = null): LinearLayout =
        vbox().apply {
            addView(text(title, 23f, true))
            if (subtitle != null) addView(text(subtitle, 12f, color = muted))
            addGap(this, 13)
        }

    private fun showTab() {
        val epoch = ++renderEpoch
        window.navigationBarColor = paper
        window.decorView.systemUiVisibility =
            if (prefs.dark) 0 else View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
        val root = vbox().apply { setBackgroundColor(paper) }
        val header = hbox().apply {
            setPadding(dp(19), dp(17), dp(19), dp(12))
            setBackgroundColor(if (prefs.dark) Color.rgb(20, 44, 49) else Color.rgb(246, 248, 242))
            gravity = Gravity.CENTER_VERTICAL
        }
        val logo = text("☎", 27f, true, Color.WHITE).apply {
            gravity = Gravity.CENTER
            background = TamasStyle.tile(this@MainActivity, 18)
        }
        header.addView(logo, LinearLayout.LayoutParams(dp(54), dp(54)))
        val heading = vbox().apply { setPadding(dp(10), 0, dp(10), 0) }
        heading.addView(text("تماس‌یار", 21f, true))
        heading.addView(text("مدیریت تماس • خانواده پیامیار", 12f, color = muted))
        header.addView(heading, LinearLayout.LayoutParams(0, -2, 1f))
        root.addView(header)
        val content = vbox().apply { setPadding(dp(16), dp(10), dp(16), dp(16)) }
        if (tab == 2) {
            root.addView(content, LinearLayout.LayoutParams(-1, 0, 1f))
            showContacts(content, epoch)
        } else {
            val scroll = ScrollView(this).apply {
                isFillViewport = false
                clipToPadding = false
            }
            scroll.addView(content)
            root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
            when (tab) {
                0 -> showHistory(content, epoch)
                1 -> showDialPad(content)
                else -> showMore(content)
            }
        }
        val nav = hbox().apply {
            setBackgroundColor(surface)
            setPadding(dp(5), dp(10), dp(5), dp(10))
        }
        listOf("تماس‌ها", "شماره‌گیر", "مخاطبین", "بیشتر").forEachIndexed { index, label ->
            nav.addView(action(label, index == tab) {
                tab = index
                showTab()
            }, LinearLayout.LayoutParams(0, dp(53), 1f).apply { setMargins(dp(3), 0, dp(3), 0) })
        }
        root.addView(nav)
        setContentView(root)
    }

    private fun showDialPad(parent: LinearLayout) {
        parent.addView(section("شماره‌گیری", "برای تماس یا ارسال پیامک، شماره را وارد کنید."))
        val entry = EditText(this).apply {
            typeface = TamasStyle.font(this@MainActivity)
            setTextColor(ink)
            setHintTextColor(muted)
            setSingleLine(true)
            inputType = InputType.TYPE_CLASS_PHONE
            textDirection = View.TEXT_DIRECTION_LTR
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            textSize = 28f
            gravity = Gravity.CENTER
            setText(digits)
            setSelection(text.length)
            addTextChangedListener(object : TextWatcher {
                override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
                override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                    digits = TamasPhone.dial(s?.toString().orEmpty())
                }
                override fun afterTextChanged(s: Editable?) {}
            })
            hint = "۰۹۱۲ ۰۰۰ ۰۰۰۰"
            background = shape(surface)
            setPadding(dp(15), dp(18), dp(15), dp(18))
        }
        parent.addView(entry)
        addGap(parent, 15)
        val dial = listOf(
            listOf("۱", "۲", "۳"), listOf("۴", "۵", "۶"),
            listOf("۷", "۸", "۹"), listOf("*", "۰", "#")
        )
        val englishDigits = mapOf('۰' to '0', '۱' to '1', '۲' to '2', '۳' to '3',
            '۴' to '4', '۵' to '5', '۶' to '6', '۷' to '7', '۸' to '8', '۹' to '9')
        dial.forEach { line ->
            val row = hbox()
            line.forEach { label ->
                row.addView(action(label) {
                    val c = label.first()
                    entry.append((englishDigits[c] ?: c).toString())
                    digits = entry.text.toString()
                }, LinearLayout.LayoutParams(0, dp(64), 1f).apply {
                    setMargins(dp(4), dp(3), dp(4), dp(3))
                })
            }
            parent.addView(row)
        }
        addGap(parent, 12)
        val buttons = hbox()
        buttons.addView(action("حذف یک رقم") {
            val value = entry.text.toString()
            if (value.isNotEmpty()) entry.setText(value.dropLast(1))
            entry.setSelection(entry.length())
            digits = entry.text.toString()
        }, LinearLayout.LayoutParams(0, dp(52), 1f).apply { setMargins(dp(4), 0, dp(4), 0) })
        buttons.addView(action("تماس  ☎", true) {
            digits = entry.text.toString().trim()
            callNumber(digits)
        }, LinearLayout.LayoutParams(0, dp(52), 2f).apply { setMargins(dp(4), 0, dp(4), 0) })
        parent.addView(buttons)
        addGap(parent)
        parent.addView(action("ارسال پیامک در پیامیار") {
            digits = TamasPhone.dial(entry.text.toString())
            openSms(digits)
        })
        addGap(parent, 15)
        if (checkSelfPermission(Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED && prefs.favorites().isNotEmpty()) {
            parent.addView(section("شماره‌های منتخب", "شماره‌های پرتکرار را از مخاطبین ستاره‌دار کن."))
            for (number in prefs.favorites().sorted().take(6)) {
                contactRow(parent, number, "منتخب", number)
            }
        }
    }

    /**
     * Content-provider queries run off the main thread. The epoch prevents late
     * results from being painted over a newly selected screen.
     */
    private fun showHistory(parent: LinearLayout, epoch: Int) {
        parent.addView(section("تماس‌های اخیر", "سوابق تماس فقط روی این گوشی خوانده می‌شوند."))
        if (!isDefaultDialer()) {
            parent.addView(text("برای نمایش سوابق، تماس‌یار باید شماره‌گیر پیش‌فرض باشد.", 14f))
            addGap(parent)
            parent.addView(action("انتخاب شماره‌گیر پیش‌فرض", true) { requestDialerRole() })
            return
        }
        if (!allowed(Manifest.permission.READ_CALL_LOG, 210)) {
            parent.addView(text("برای نمایش سوابق تماس، مجوز موردنیاز را تأیید کنید.", 13f))
            return
        }
        val filterNames = listOf("همه", "بی‌پاسخ", "ورودی", "خروجی")
        val types = listOf(0, CallLog.Calls.MISSED_TYPE,
            CallLog.Calls.INCOMING_TYPE, CallLog.Calls.OUTGOING_TYPE)
        val controls = hbox()
        filterNames.forEachIndexed { index, title ->
            val control = action(title, historyFilter == index) {
                historyFilter = index
                showTab()
            }
            control.textSize = 12f * prefs.scale()
            controls.addView(control, LinearLayout.LayoutParams(0, dp(46), 1f).apply {
                setMargins(dp(2), 0, dp(2), 0)
            })
        }
        parent.addView(controls)
        addGap(parent, 12)
        val rows = vbox()
        rows.addView(text("در حال خواندن سوابق تماس…", 13f, color = muted))
        parent.addView(rows)
        val historyType = historyFilter
        Thread {
            val entries = mutableListOf<Triple<String, String, String>>()
            var error: String? = null
            try {
                val selection = if (historyType == 0) null else CallLog.Calls.TYPE + "=?"
                val args = if (historyType == 0) null else arrayOf(types[historyType].toString())
                val cursor = contentResolver.query(CallLog.Calls.CONTENT_URI,
                    arrayOf(CallLog.Calls.NUMBER, CallLog.Calls.TYPE,
                        CallLog.Calls.DATE, CallLog.Calls.DURATION),
                    selection, args, CallLog.Calls.DATE + " DESC")
                if (cursor == null) error = "دسترسی به تاریخچه تماس ممکن نیست."
                else cursor.use { c ->
                    val numberAt = c.getColumnIndexOrThrow(CallLog.Calls.NUMBER)
                    val typeAt = c.getColumnIndexOrThrow(CallLog.Calls.TYPE)
                    val dateAt = c.getColumnIndexOrThrow(CallLog.Calls.DATE)
                    val durationAt = c.getColumnIndexOrThrow(CallLog.Calls.DURATION)
                    val df = SimpleDateFormat("yyyy/MM/dd HH:mm", Locale("fa", "IR"))
                    while (c.moveToNext() && entries.size < 100) {
                        val number = c.getString(numberAt).orEmpty()
                        val type = when (c.getInt(typeAt)) {
                            CallLog.Calls.INCOMING_TYPE -> "ورودی"
                            CallLog.Calls.OUTGOING_TYPE -> "خروجی"
                            CallLog.Calls.MISSED_TYPE -> "بی‌پاسخ"
                            CallLog.Calls.REJECTED_TYPE -> "ردشده"
                            else -> "تماس"
                        }
                        val info = type + " • " + df.format(Date(c.getLong(dateAt))) +
                            " • " + c.getLong(durationAt) + " ثانیه"
                        entries.add(Triple(if (number.isBlank()) "شماره خصوصی" else number,
                            info, number))
                    }
                }
            } catch (_: SecurityException) {
                error = "مجوز نمایش سوابق تماس کافی نیست."
            } catch (_: Exception) {
                error = "در خواندن سوابق تماس خطایی رخ داد."
            }
            runOnUiThread {
                if (isFinishing || isDestroyed || renderEpoch != epoch || tab != 0)
                    return@runOnUiThread
                rows.removeAllViews()
                if (error != null) rows.addView(text(error!!, 13f, color = muted))
                else if (entries.isEmpty()) rows.addView(text("تماسی برای این فیلتر پیدا نشد.", 13f))
                else entries.forEach { (title, info, number) ->
                    contactRow(rows, title, info, number)
                }
            }
        }.start()
    }

    private fun isFavoriteContact(contact: TamasContact): Boolean =
        contact.starred || contact.phones.any { prefs.isFavorite(it) }

    private fun showContacts(parent: LinearLayout, epoch: Int) {
        parent.addView(section("همه مخاطبین گوشی",
            "دفترچه مشترک اندروید و پیامیار؛ حتی مخاطبین بدون شماره"))
        val actions = hbox()
        actions.addView(action("＋ افزودن", true) {
            try {
                startActivity(Intent(Intent.ACTION_INSERT).setType(
                    ContactsContract.Contacts.CONTENT_TYPE))
            } catch (_: Exception) {
                Toast.makeText(this, "برنامه مخاطبین پیدا نشد.", Toast.LENGTH_LONG).show()
            }
        }, LinearLayout.LayoutParams(0, dp(47), 1f).apply {
            setMargins(dp(3), 0, dp(3), 0)
        })
        actions.addView(action("↻ تازه‌سازی") {
            contactsCache = null
            showTab()
        }, LinearLayout.LayoutParams(0, dp(47), 1f).apply {
            setMargins(dp(3), 0, dp(3), 0)
        })
        parent.addView(actions)
        addGap(parent, 10)
        if (!allowed(Manifest.permission.READ_CONTACTS, 211)) {
            parent.addView(text("برای نمایش همه مخاطبین سیم‌کارت، حساب‌ها و گوشی، دسترسی مخاطبین را تأیید کنید.", 13f))
            return
        }
        val search = EditText(this).apply {
            typeface = TamasStyle.font(this@MainActivity)
            textSize = 16f * prefs.scale()
            setTextColor(ink)
            setHintTextColor(muted)
            hint = "جست‌وجوی سریع نام یا شماره…"
            setSingleLine(true)
            setText(filter)
            setPadding(dp(15), dp(13), dp(15), dp(13))
            background = shape(surface)
        }
        parent.addView(search)
        addGap(parent, 8)
        val switches = hbox()
        switches.addView(action(if (favoriteOnly) "★ منتخب‌ها" else "☆ فقط منتخب‌ها", favoriteOnly) {
            favoriteOnly = !favoriteOnly
            filter = search.text.toString()
            showTab()
        }, LinearLayout.LayoutParams(0, dp(44), 1f).apply {
            setMargins(dp(2), 0, dp(2), 0)
        })
        switches.addView(action(
            if (prefs.favoritesFirst) "★ منتخب‌ها ابتدا" else "الفبایی"
        ) {
            prefs.favoritesFirst = !prefs.favoritesFirst
            filter = search.text.toString()
            showTab()
        }, LinearLayout.LayoutParams(0, dp(44), 1f).apply {
            setMargins(dp(2), 0, dp(2), 0)
        })
        parent.addView(switches)
        val status = text("در حال خواندن مخاطبین گوشی…", 12f, color = muted)
        parent.addView(status)
        val adapter = TamasContactAdapter(this,
            onOpen = { openContactActions(it) },
            isFavorite = { isFavoriteContact(it) })
        val list = ListView(this).apply {
            divider = android.graphics.drawable.ColorDrawable(Color.TRANSPARENT)
            dividerHeight = dp(5)
            clipToPadding = false
            setPadding(0, dp(5), 0, dp(8))
            isFastScrollEnabled = true
            this.adapter = adapter
        }
        parent.addView(list, LinearLayout.LayoutParams(-1, 0, 1f))
        val applyFilter = {
            val all = contactsCache.orEmpty()
            val matches = TamasContactRepository.search(
                all, search.text.toString(), favoriteOnly,
                prefs.favorites(), prefs.favoritesFirst
            )
            adapter.submit(matches)
            status.text = if (all.isEmpty()) "مخاطبی در گوشی یافت نشد."
                else matches.size.toString() + " مخاطب از " + all.size + " مخاطب گوشی"
        }
        search.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                filter = s?.toString().orEmpty()
                if (contactsCache != null) applyFilter()
            }
            override fun afterTextChanged(s: Editable?) {}
        })
        if (contactsCache != null) applyFilter()
        val loadToken = ++contactsListEpoch
        Thread {
            var found: List<TamasContact>? = null
            var issue: String? = null
            try { found = TamasContactRepository.load(applicationContext) }
            catch (_: SecurityException) { issue = "دسترسی مخاطبین محدود شده است." }
            catch (_: Exception) { issue = "خواندن مخاطبین با مشکل روبه‌رو شد؛ دوباره تلاش کنید." }
            runOnUiThread {
                if (isFinishing || isDestroyed || tab != 2 ||
                    renderEpoch != epoch || contactsListEpoch != loadToken) return@runOnUiThread
                if (issue != null) {
                    if (contactsCache == null) status.text = issue
                    return@runOnUiThread
                }
                contactsCache = found.orEmpty()
                applyFilter()
            }
        }.start()
    }

    private fun openContactActions(contact: TamasContact) {
        if (contact.phones.isEmpty()) {
            openSystemContact(contact)
            return
        }
        val options = contact.phones.map { "☎  " + it }.toMutableList()
        options.add("مشاهده و ویرایش مخاطب در دفترچه گوشی")
        AlertDialog.Builder(this)
            .setTitle(contact.name)
            .setItems(options.toTypedArray()) { _, position ->
                if (position == contact.phones.size) openSystemContact(contact)
                else openNumberActions(contact.name, contact.phones[position])
            }
            .setNegativeButton("بستن", null)
            .show()
    }

    private fun openSystemContact(contact: TamasContact) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW,
                ContentUris.withAppendedId(ContactsContract.Contacts.CONTENT_URI, contact.id)))
        } catch (_: Exception) {
            Toast.makeText(this, "صفحه مخاطب در دسترس نیست.", Toast.LENGTH_LONG).show()
        }
    }

    private fun openNumberActions(name: String, number: String) {
        val starred = prefs.isFavorite(number)
        val labels = arrayOf(
            "تماس با " + number,
            "ارسال پیام با پیامیار",
            "کپی شماره",
            "اشتراک‌گذاری شماره",
            if (starred) "حذف از منتخب‌های تماس‌یار" else "افزودن به منتخب‌های تماس‌یار"
        )
        AlertDialog.Builder(this).setTitle(name).setItems(labels) { _, position ->
            when (position) {
                0 -> callNumber(number)
                1 -> openSms(number)
                2 -> {
                    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("phone", number))
                    Toast.makeText(this, "شماره کپی شد.", Toast.LENGTH_SHORT).show()
                }
                3 -> try {
                    startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, name + "\n" + number)
                    }, "اشتراک‌گذاری شماره"))
                } catch (_: Exception) {
                    Toast.makeText(this, "اشتراک‌گذاری ممکن نیست.", Toast.LENGTH_SHORT).show()
                }
                4 -> {
                    prefs.toggleFavorite(number)
                    showTab()
                }
            }
        }.setNegativeButton("بستن", null).show()
    }

    private fun contactRow(parent: LinearLayout, title: String, subtitle: String, number: String) {
        val card = vbox().apply {
            background = shape(surface)
            setPadding(dp(10), dp(10), dp(10), dp(10))
        }
        val heading = hbox().apply { gravity = Gravity.CENTER_VERTICAL }
        val initials = text(TamasPhone.initials(title), 17f, true, TamasStyle.teal).apply {
            gravity = Gravity.CENTER
            background = shape(if (prefs.dark) Color.rgb(35, 76, 74) else TamasStyle.mist)
        }
        heading.addView(initials, LinearLayout.LayoutParams(dp(46), dp(46)))
        val identity = vbox().apply { setPadding(dp(7), 0, dp(7), 0) }
        identity.addView(text(title, 16f, true))
        identity.addView(text(subtitle, 12f, color = muted))
        heading.addView(identity, LinearLayout.LayoutParams(0, -2, 1f))
        if (number.isNotBlank()) {
            heading.addView(action(if (prefs.isFavorite(number)) "★" else "☆") {
                val added = prefs.toggleFavorite(number)
                Toast.makeText(this,
                    if (added) "به منتخب‌ها افزوده شد." else "از منتخب‌ها حذف شد.",
                    Toast.LENGTH_SHORT).show()
                showTab()
            }, LinearLayout.LayoutParams(dp(49), dp(49)))
        }
        card.addView(heading)
        if (number.isNotBlank()) {
            addGap(card, 6)
            val buttons = hbox()
            buttons.addView(action("تماس") { callNumber(number) },
                LinearLayout.LayoutParams(0, dp(42), 1f).apply { setMargins(dp(3), 0, dp(3), 0) })
            buttons.addView(action("پیامیار") { openSms(number) },
                LinearLayout.LayoutParams(0, dp(42), 1f).apply { setMargins(dp(3), 0, dp(3), 0) })
            card.addView(buttons)
        }
        parent.addView(card)
        addGap(parent)
    }

    private fun settingCard(parent: LinearLayout, title: String, description: String,
        button: String, onClick: () -> Unit
    ) {
        val card = vbox().apply {
            background = shape(surface)
            setPadding(dp(15), dp(13), dp(15), dp(13))
        }
        card.addView(text(title, 16f, true))
        card.addView(text(description, 12f, color = muted))
        addGap(card, 7)
        card.addView(action(button, false, onClick))
        parent.addView(card)
        addGap(parent, 11)
    }

    private fun showMore(parent: LinearLayout) {
        parent.addView(section("تنظیمات", "دسترسی آسان، شخصی‌سازی و به‌روزرسانی تماس‌یار"))
        settingCard(parent, "برنامه تلفن پیش‌فرض",
            if (isDefaultDialer()) "تماس‌یار شماره‌گیر پیش‌فرض گوشی است."
            else "برای نمایش سوابق و مدیریت تماس‌ها، اجازه نقش تلفن را به تماس‌یار بدهید.",
            if (isDefaultDialer()) "فعال است ✓" else "فعال کردن تماس‌یار") {
            if (!isDefaultDialer()) requestDialerRole() else
                Toast.makeText(this, "تماس‌یار فعال است.", Toast.LENGTH_SHORT).show()
        }
        settingCard(parent, "دسترسی‌ها و حریم خصوصی",
            "مخاطبین، سابقه تماس و اعلان‌ها فقط با مجوز سیستم خوانده می‌شوند.",
            "مدیریت مجوزها") {
            val i = Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:" + packageName))
            startActivity(i)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            settingCard(parent, "اجازه اعلان‌ها",
                if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED) "اعلان‌های تماس و به‌روزرسانی مجاز هستند."
                else "برای دریافت هشدار نسخه جدید، نمایش اعلان‌ها را فعال کنید.",
                "مدیریت اعلان‌ها") {
                if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED &&
                    requestedPermissions.add(Manifest.permission.POST_NOTIFICATIONS)) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 213)
                } else {
                    startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:" + packageName)))
                }
            }
        }

        parent.addView(section("به‌روزرسانی برنامه", "نسخه‌ها از سایت رسمی هنر مردمی بررسی می‌شوند."))
        settingCard(parent, "بررسی خودکار نسخه جدید",
            if (prefs.autoUpdates) "فعال؛ هنگام اجرای برنامه و در پس‌زمینه با رعایت محدودیت باتری اندروید نسخه جدید بررسی می‌شود."
            else "غیرفعال؛ فقط با درخواست شما بررسی انجام می‌شود.",
            if (prefs.autoUpdates) "خاموش کردن بررسی خودکار" else "روشن کردن بررسی خودکار") {
            prefs.autoUpdates = !prefs.autoUpdates
            prefs.lastChecked = 0L
            TamasUpdateWorker.configure(this)
            showTab()
            if (prefs.autoUpdates) TamasUpdater.check(this, automatic = true) { _, _ -> }
        }
        settingCard(parent, "انتخاب سیم‌کارت تماس",
            if (prefs.chooseSim) "اگر گوشی چند حساب تماس فعال داشته باشد، می‌توانید سیم‌کارت را هنگام تماس انتخاب کنید."
            else "سیم‌کارت بر اساس تنظیمات پیش‌فرض اندروید انتخاب می‌شود.",
            if (prefs.chooseSim) "استفاده از سیم‌کارت پیش‌فرض" else "فعال کردن انتخاب سیم‌کارت") {
            prefs.chooseSim = !prefs.chooseSim
            showTab()
        }
        settingCard(parent, "دانلود و نصب نسخه جدید",
            "بررسی آنلاین نسخه، نمایش تغییرات و نصب فقط پس از تأیید شما. " +
                "فایل نصب قبل از اجرا با SHA-256 کنترل می‌شود.",
            "بررسی نسخه جدید") { checkForUpdates() }
        settingCard(parent, "صفحه دانلود رسمی",
            "اگر نسخه منتشرشده‌ای موجود باشد، در سایت هنر مردمی نمایش داده می‌شود.",
            "صفحه تماس‌یار") {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(TamasUpdater.PAGE_URL)))
        }

        parent.addView(section("ظاهر و خوانایی", "هماهنگ با رنگ فیروزه‌ای و طلایی پیامیار"))
        settingCard(parent, "حالت نمایش",
            if (prefs.dark) "حالت تیره فعال است." else "حالت روشن فعال است.",
            if (prefs.dark) "تغییر به حالت روشن" else "تغییر به حالت تیره") {
            prefs.dark = !prefs.dark
            showTab()
        }
        val scales = listOf("کوچک", "استاندارد", "درشت")
        settingCard(parent, "اندازه نوشته‌ها",
            "اندازه فعلی: " + scales[prefs.textSize] + " • فونت فارسی وزیرمتن",
            "تغییر اندازه") {
            prefs.textSize = (prefs.textSize + 1) % 3
            showTab()
        }

        parent.addView(section("ارتباط و درباره برنامه", "دو برنامه مستقل، دفترچه مخاطبین مشترک"))
        settingCard(parent, "پیامیار",
            "برای ارسال و دریافت پیامک، پیامیار را باز کنید. تماس‌یار مستقل باقی می‌ماند.",
            "رفتن به پیامیار") { openPayamYar() }
        val version = try {
            packageManager.getPackageInfo(packageName, 0).versionName
        } catch (_: Exception) { "?" }
        settingCard(parent, "درباره تماس‌یار",
            "نسخه " + version + " • شناسه: " + packageName +
                "\nضبط تماس، تشخیص هوشمند مزاحم و انتخاب اختصاصی سیم‌کارت هنوز فعال نیستند.",
            "راهنمای حریم خصوصی") {
            AlertDialog.Builder(this).setTitle("حریم خصوصی تماس‌یار")
                .setMessage("مخاطبین و سوابق تماس فقط روی گوشی خوانده می‌شوند. " +
                    "داده تماس یا مخاطبین به پیامیار و سایت هنر مردمی ارسال نمی‌شود. " +
                    "ارتباط شبکه صرفاً برای بررسی نسخه‌های منتشرشده است. " +
                    "برای حذف مجوزها از تنظیمات اندروید استفاده کنید.")
                .setPositiveButton("متوجه شدم", null).show()
        }
    }

    private fun checkForUpdates() {
        Toast.makeText(this, "در حال بررسی نسخه جدید…", Toast.LENGTH_SHORT).show()
        TamasUpdater.check(this) { release, message ->
            if (isFinishing || isDestroyed) return@check
            if (release == null) {
                AlertDialog.Builder(this).setTitle("وضعیت به‌روزرسانی")
                    .setMessage(message ?: "نسخه جدیدی موجود نیست.")
                    .setPositiveButton("باشه", null).show()
            } else {
                TamasUpdater.confirmInstall(this, release) { notice ->
                    if (!isFinishing) Toast.makeText(this, notice, Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private fun allowed(permission: String, requestCode: Int): Boolean {
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) return true
        if (requestedPermissions.add(permission)) requestPermissions(arrayOf(permission), requestCode)
        return false
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, results)
        if (requestCode == 210 || requestCode == 211) showTab()
        if (requestCode == 212 && results.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            pendingNumber?.let { pendingNumber = null; callNumber(it) }
    }

    private fun isDefaultDialer(): Boolean {
        val tm = getSystemService(TELECOM_SERVICE) as TelecomManager
        return tm.defaultDialerPackage == packageName
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 301) {
            showTab()
            Toast.makeText(this,
                if (isDefaultDialer()) "تماس‌یار به‌عنوان شماره‌گیر پیش‌فرض انتخاب شد."
                else "برنامه تلفن پیش‌فرض تغییر نکرد.", Toast.LENGTH_LONG).show()
        }
    }

    private fun requestDialerRole() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = getSystemService(ROLE_SERVICE) as RoleManager
            if (roles.isRoleAvailable(RoleManager.ROLE_DIALER))
                startActivityForResult(roles.createRequestRoleIntent(RoleManager.ROLE_DIALER), 301)
        } else {
            val telecom = getSystemService(TELECOM_SERVICE) as TelecomManager
            startActivityForResult(Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER)
                .putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, packageName), 301)
        }
    }

    private fun callNumber(number: String) {
        if (number.isBlank()) return
        val target = Uri.fromParts("tel", number, null)
        if (!isDefaultDialer()) {
            val currentDialer = (getSystemService(TELECOM_SERVICE) as TelecomManager).defaultDialerPackage
            if (!currentDialer.isNullOrBlank() && currentDialer != packageName) {
                try {
                    startActivity(Intent(Intent.ACTION_DIAL, target).setPackage(currentDialer))
                    return
                } catch (_: Exception) { /* Fall back to role request below. */ }
            }
            requestDialerRole()
            return
        }
        if (!allowed(Manifest.permission.CALL_PHONE, 212)) {
            pendingNumber = number
            return
        }
        if (checkSelfPermission(Manifest.permission.CALL_PHONE) !=
            PackageManager.PERMISSION_GRANTED) {
            Toast.makeText(this, "مجوز تماس هنوز فعال نیست.", Toast.LENGTH_LONG).show()
            return
        }
        val telecom = getSystemService(TELECOM_SERVICE) as TelecomManager
        if (prefs.chooseSim && checkSelfPermission(Manifest.permission.READ_PHONE_STATE) ==
            PackageManager.PERMISSION_GRANTED) {
            try {
                val accounts = telecom.callCapablePhoneAccounts
                if (accounts.size > 1) {
                    val options = accounts.mapIndexed { index, account ->
                        val label = telecom.getPhoneAccount(account)?.label?.toString()
                        if (label.isNullOrBlank()) "سیم‌کارت ${index + 1}" else label
                    }.toTypedArray()
                    AlertDialog.Builder(this)
                        .setTitle("انتخاب سیم‌کارت")
                        .setItems(options) { _, index -> placeOutgoing(target, accounts[index]) }
                        .setNeutralButton("حساب پیش‌فرض") { _, _ -> placeOutgoing(target, null) }
                        .setNegativeButton("انصراف", null)
                        .show()
                    return
                }
            } catch (_: SecurityException) {
                // Android can show its own SIM selection if the role lacks account access.
            } catch (_: Exception) { }
        }
        placeOutgoing(target, null)
    }

    private fun placeOutgoing(uri: Uri, account: PhoneAccountHandle?) {
        if (checkSelfPermission(Manifest.permission.CALL_PHONE) !=
            PackageManager.PERMISSION_GRANTED || !isDefaultDialer()) {
            Toast.makeText(this, "ابتدا نقش تلفن و مجوز تماس را فعال کنید.",
                Toast.LENGTH_LONG).show()
            return
        }
        val extras = Bundle()
        if (account != null) extras.putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, account)
        try {
            (getSystemService(TELECOM_SERVICE) as TelecomManager).placeCall(uri, extras)
        } catch (_: SecurityException) {
            Toast.makeText(this, "مجوز برقراری تماس وجود ندارد.", Toast.LENGTH_LONG).show()
        } catch (_: Exception) {
            Toast.makeText(this, "برقراری تماس ممکن نشد. تلفن و سیم‌کارت را بررسی کنید.",
                Toast.LENGTH_LONG).show()
        }
    }

    private fun openSms(number: String) {
        if (number.isBlank()) return
        val uri = Uri.fromParts("smsto", number, null)
        val intent = Intent(Intent.ACTION_SENDTO, uri)
        try {
            startActivity(Intent(intent).setPackage("ir.honarmardomi.payamyar"))
        } catch (_: ActivityNotFoundException) {
            try { startActivity(intent) } catch (_: ActivityNotFoundException) {
                android.widget.Toast.makeText(this, "برنامه پیامک پیدا نشد.", android.widget.Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun openPayamYar() {
        val launch = packageManager.getLaunchIntentForPackage("ir.honarmardomi.payamyar")
        if (launch != null) startActivity(launch)
        else startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://honarmardomi.ir/payamyar/")))
    }
}
