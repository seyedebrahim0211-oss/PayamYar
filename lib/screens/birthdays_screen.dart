import 'package:flutter/material.dart';
import '../app_store.dart';
import '../birthdays.dart';
import '../jalali.dart';
import '../sms_bridge.dart';
import 'widgets.dart';

/// Contacts' birthdays: upcoming list, automatic greeting SMS and day-before reminders.
class BirthdaysScreen extends StatefulWidget {
  final AppStore store;
  const BirthdaysScreen({super.key, required this.store});

  @override
  State<BirthdaysScreen> createState() => _BirthdaysScreenState();
}

class _BirthdaysScreenState extends State<BirthdaysScreen> {
  final birthdays = BirthdayStore();

  @override
  void initState() {
    super.initState();
    birthdays.load();
  }

  @override
  void dispose() {
    birthdays.dispose();
    super.dispose();
  }

  Future<void> _edit([Birthday? existing]) async {
    final result = await showModalBottomSheet<Birthday>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _BirthdayEditor(store: widget.store, initial: existing),
    );
    if (result != null) await birthdays.upsert(result);
  }

  Future<void> _delete(Birthday b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف تولد'),
        content: Text('تولد ${b.name} از فهرست حذف شود؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) await birthdays.remove(b.id);
  }

  Future<void> _sendNow(Birthday b) async {
    final name = b.name;
    final ok = await SmsBridge.birthdaySendNow(b.id);
    widget.store.onNotice?.call(ok ? 'تبریک تولد برای $name فرستاده شد.' : 'ارسال انجام نشد؛ دسترسی پیامک را بررسی کنید.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('تولد مخاطبین')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.cake_outlined),
        label: const Text('افزودن تولد'),
      ),
      body: ListenableBuilder(
        listenable: birthdays,
        builder: (context, child) {
          final list = birthdays.upcoming;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              _Hero(count: list.length, next: list.isEmpty ? null : list.first),
              const SizedBox(height: 14),
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.cake_outlined,
                  title: 'هنوز تولدی ثبت نشده',
                  subtitle: 'تولد مخاطبان را اضافه کنید تا پیامیار روز تولد، خودکار تبریک بفرستد.',
                ),
              for (final b in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _edit(b),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          _DaysBadge(days: daysUntil(b.month, b.day), enabled: b.enabled),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(b.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                              const SizedBox(height: 2),
                              Text(_subtitle(b), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                            ]),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) {
                              switch (v) {
                                case 'send':
                                  _sendNow(b);
                                case 'toggle':
                                  birthdays.upsert(b.copyWith(enabled: !b.enabled));
                                case 'delete':
                                  _delete(b);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'send', child: Text('ارسال تبریک همین حالا')),
                              PopupMenuItem(value: 'toggle', child: Text(b.enabled ? 'غیرفعال کردن' : 'فعال کردن')),
                              const PopupMenuItem(value: 'delete', child: Text('حذف')),
                            ],
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              if (list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'پیامک تبریک در ساعت تعیین‌شده، حتی وقتی پیامیار بسته است، ارسال می‌شود. برای دقت زمان، «دسترسی‌های ویژه» را در تنظیمات کامل کنید.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _subtitle(Birthday b) {
    final days = daysUntil(b.month, b.day);
    final when = DateTime.now().add(Duration(days: days));
    final age = b.ageOn(Jalali.fromGregorian(when.year, when.month, when.day)[0]);
    final ageText = age == null ? '' : ' • ${Jalali.digits(age)} سالگی';
    final mode = !b.enabled ? 'غیرفعال' : b.autoSend ? 'ارسال خودکار ساعت ${b.timeLabel}' : 'فقط یادآوری';
    return '${b.dateLabel}$ageText • $mode';
  }
}

class _Hero extends StatelessWidget {
  final int count;
  final Birthday? next;
  const _Hero({required this.count, required this.next});

  @override
  Widget build(BuildContext context) {
    final n = next;
    final days = n == null ? null : daysUntil(n.month, n.day);
    final when = days == null ? '' : days == 0 ? 'امروز' : days == 1 ? 'فردا' : '${Jalali.digits(days)} روز دیگر';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFB4537A), Color(0xFF7A3E8F), Color(0xFF3F3A88)],
        ),
      ),
      child: Row(children: [
        const Text('🎂', style: TextStyle(fontSize: 42)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n == null ? 'تقویم تولد' : 'تولد بعدی: ${n.name}',
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(n == null ? 'تبریک خودکار و یادآور یک روز قبل' : '$when • ${n.dateLabel}',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 4),
            Text('${Jalali.digits(count)} تولد ثبت شده', style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

class _DaysBadge extends StatelessWidget {
  final int days;
  final bool enabled;
  const _DaysBadge({required this.days, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = days == 0;
    final bg = !enabled ? scheme.surfaceContainerHighest : today ? const Color(0xFFB4537A) : scheme.primaryContainer;
    final fg = !enabled ? scheme.onSurfaceVariant : today ? Colors.white : scheme.onPrimaryContainer;
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      alignment: Alignment.center,
      child: today
          ? const Text('🎉', style: TextStyle(fontSize: 24))
          : Column(mainAxisSize: MainAxisSize.min, children: [
              Text(Jalali.digits(days), style: TextStyle(color: fg, fontWeight: FontWeight.w900, fontSize: 17, height: 1.1)),
              Text('روز', style: TextStyle(color: fg, fontSize: 11, height: 1.2)),
            ]),
    );
  }
}

class _BirthdayEditor extends StatefulWidget {
  final AppStore store;
  final Birthday? initial;
  const _BirthdayEditor({required this.store, this.initial});

  @override
  State<_BirthdayEditor> createState() => _BirthdayEditorState();
}

class _BirthdayEditorState extends State<_BirthdayEditor> {
  late final name = TextEditingController(text: widget.initial?.name ?? '');
  late final number = TextEditingController(text: widget.initial?.number ?? '');
  late final message = TextEditingController(text: widget.initial?.message ?? defaultBirthdayMessage);
  late int month = widget.initial?.month ?? 1;
  late int day = widget.initial?.day ?? 1;
  late int year = widget.initial?.year ?? 0;
  late TimeOfDay time = TimeOfDay(hour: widget.initial?.hour ?? 9, minute: widget.initial?.minute ?? 0);
  late bool autoSend = widget.initial?.autoSend ?? true;
  late bool remind = widget.initial?.remind ?? true;
  late bool enabled = widget.initial?.enabled ?? true;

  @override
  void dispose() {
    name.dispose();
    number.dispose();
    message.dispose();
    super.dispose();
  }

  int get maxDay => month <= 6 ? 31 : 30;

  Future<void> _pickContact() async {
    final picked = await SmsBridge.pickContact();
    if (picked == null || !mounted) return;
    final clean = SmsBridge.normalizeNumber(picked).replaceAll(RegExp(r'[\s()-]'), '');
    setState(() {
      number.text = clean;
      if (name.text.trim().isEmpty) {
        final shown = widget.store.displayName(clean);
        name.text = shown == clean ? '' : shown;
      }
    });
  }

  void _insert(String tag) {
    final v = message.value;
    final start = v.selection.isValid ? v.selection.start : v.text.length;
    final end = v.selection.isValid ? v.selection.end : v.text.length;
    message.value = TextEditingValue(
      text: v.text.replaceRange(start, end, tag),
      selection: TextSelection.collapsed(offset: start + tag.length),
    );
  }

  void _save() {
    final n = SmsBridge.normalizeNumber(number.text).replaceAll(RegExp(r'[\s()-]'), '');
    if (!RegExp(r'^\+?\d{7,15}$').hasMatch(n)) {
      widget.store.onNotice?.call('شماره موبایل معتبر وارد کنید.');
      return;
    }
    final title = name.text.trim().isEmpty ? n : name.text.trim();
    Navigator.of(context).pop(Birthday(
      id: widget.initial?.id ?? BirthdayStore.newId(),
      name: title,
      number: n,
      month: month,
      day: day.clamp(1, maxDay).toInt(),
      year: year,
      hour: time.hour,
      minute: time.minute,
      message: message.text.trim().isEmpty ? defaultBirthdayMessage : message.text.trim(),
      enabled: enabled,
      autoSend: autoSend,
      remind: remind,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final jy = Jalali.fromGregorian(now.year, now.month, now.day)[0];
    final preview = Birthday(id: 'p', name: name.text.trim().isEmpty ? 'نام مخاطب' : name.text.trim(), number: '',
        month: month, day: day, year: year, message: message.text).render(jy);
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          Text(widget.initial == null ? 'تولد جدید' : 'ویرایش تولد', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          TextField(
            controller: number,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'شماره موبایل',
              suffixIcon: IconButton(
                tooltip: 'انتخاب از مخاطبین',
                onPressed: _pickContact,
                icon: const Icon(Icons.contacts_outlined),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'نام'), onChanged: (_) => setState(() {})),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('days$maxDay'),
                initialValue: day.clamp(1, maxDay).toInt(),
                decoration: const InputDecoration(labelText: 'روز'),
                items: [for (var d = 1; d <= maxDay; d++) DropdownMenuItem(value: d, child: Text(Jalali.digits(d)))],
                onChanged: (v) => setState(() => day = v ?? day),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<int>(
                initialValue: month,
                decoration: const InputDecoration(labelText: 'ماه'),
                items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(Jalali.months[m - 1]))],
                onChanged: (v) => setState(() {
                  month = v ?? month;
                  day = day.clamp(1, maxDay).toInt();
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: year,
                decoration: const InputDecoration(labelText: 'سال'),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('نامشخص')),
                  for (var y = jy; y >= jy - 100; y--) DropdownMenuItem(value: y, child: Text(Jalali.digits(y))),
                ],
                onChanged: (v) => setState(() => year = v ?? 0),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('ارسال خودکار پیامک تبریک'),
            value: autoSend,
            onChanged: (v) => setState(() => autoSend = v),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.schedule_rounded, color: scheme.primary),
            title: const Text('ساعت ارسال یا یادآوری'),
            trailing: Text(Jalali.digits('$hh:$mm'), style: const TextStyle(fontWeight: FontWeight.w800)),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: time, cancelText: 'انصراف', confirmText: 'تأیید');
              if (t != null) setState(() => time = t);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('یادآوری یک روز قبل'),
            value: remind,
            onChanged: (v) => setState(() => remind = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('فعال'),
            value: enabled,
            onChanged: (v) => setState(() => enabled = v),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: message,
            minLines: 3,
            maxLines: 6,
            maxLength: 600,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'متن تبریک'),
          ),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final tag in const ['{نام}', '{نام کامل}', '{سن}'])
              ActionChip(label: Text(tag), onPressed: () => setState(() => _insert(tag))),
            ActionChip(
              avatar: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('متن آماده'),
              onPressed: () async {
                final picked = await showModalBottomSheet<String>(
                  context: context,
                  showDragHandle: true,
                  builder: (ctx) => ListView(shrinkWrap: true, children: [
                    for (final t in birthdayTemplates)
                      ListTile(title: Text(t, maxLines: 3), onTap: () => Navigator.pop(ctx, t)),
                  ]),
                );
                if (picked != null) setState(() => message.text = picked);
              },
            ),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('پیش‌نمایش', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 12)),
              const SizedBox(height: 6),
              Text(preview),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check_rounded), label: const Text('ذخیره')),
        ],
      ),
    );
  }
}
