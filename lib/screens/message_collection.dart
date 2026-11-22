import 'dart:async';
import 'package:flutter/material.dart';
import '../app_store.dart';
import '../bank_privacy.dart';
import '../jalali.dart';
import '../message_logic.dart';
import '../message_search.dart';
import '../smart/smart_sms_engine.dart';
import 'conversation_screen.dart';
import 'widgets.dart';

enum CollectionKind {
  search('جست‌وجوی پیشرفته'), codes('کدهای تأیید'), starred('پیام‌های ستاره‌دار'), cleanup('پاک‌سازی پیشنهادی');
  const CollectionKind(this.title);
  final String title;
}

class MessageCollection extends StatefulWidget {
  const MessageCollection({super.key, required this.store, required this.kind});
  final AppStore store;
  final CollectionKind kind;
  @override
  State<MessageCollection> createState() => _MessageCollectionState();
}

class _MessageCollectionState extends State<MessageCollection> {
  static final _link = RegExp(r'(https?://|www\.|\b[a-z0-9-]+\.(ir|com|org|net)\b)', caseSensitive: false);
  static final _amount = RegExp(r'[0-9۰-۹٠-٩][0-9۰-۹٠-٩,.٬،\s]*(ریال|تومان)');
  List<MessageRecord> rows = [];
  final selected = <int>{};
  String query = '';
  bool linksOnly = false, amountsOnly = false, scanning = true, deleting = false;
  MessageCategory? category;
  DateTimeRange? period;
  int generation = 0;
  Timer? timer;
  bool get cleanup => widget.kind == CollectionKind.cleanup;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_schedule);
    _schedule();
  }

  @override
  void dispose() {
    widget.store.removeListener(_schedule);
    timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    timer?.cancel();
    final token = ++generation;
    setState(() => scanning = true);
    timer = Timer(const Duration(milliseconds: 180), () => _scan(token));
  }

  Future<void> _scan(int token) async {
    final store = widget.store;
    final found = <MessageRecord>[];
    final terms = MessageSearch.terms(query);
    final now = DateTime.now();
    final end = period?.end;
    final until = end == null ? null : DateTime(end.year, end.month, end.day + 1);
    final budget = Stopwatch()..start();
    final source = store.messages;
    for (var i = 0; i < source.length; i++) {
      if (budget.elapsedMilliseconds >= 5) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (!mounted || token != generation) return;
        budget.reset();
      }
      final m = source[i];
      if (widget.kind == CollectionKind.starred && !store.starredIds.contains(m.id)) continue;
      if (cleanup && (m.id == null || m.outgoing || store.starredIds.contains(m.id) ||
          store.pinnedMessageId(m.sender) == m.id)) { continue; }
      if (cleanup || widget.kind == CollectionKind.codes) {
        if (m.outgoing) continue;
        final otp = SmartSmsEngine.analyze(m.sender, m.body).containsOneTimeCode;
        if (cleanup) {
          final age = now.difference(m.date);
          if (!(otp && age >= const Duration(days: 1)) &&
              !(m.read && age >= const Duration(days: 30) && MessageLogic.category(m) == MessageCategory.advertising)) { continue; }
        } else if (!otp) { continue; }
      }
      if (period != null && (m.date.isBefore(period!.start) || !m.date.isBefore(until!))) continue;
      if (category != null && MessageLogic.category(m) != category) continue;
      if (linksOnly && !_link.hasMatch(m.body)) continue;
      if (amountsOnly && !_amount.hasMatch(m.body)) continue;
      if (terms.isNotEmpty && !MessageSearch.containsTerms(
          '${MessageSearch.normalize(store.displayName(m.sender))} ${MessageSearch.normalize(m.sender)} '
          '${MessageSearch.phoneAliases(m.sender)} ${MessageSearch.indexedBody(m)}', terms)) { continue; }
      found.add(m);
    }
    if (mounted && token == generation) {
      final visible = found.map((m) => m.id).toSet();
      setState(() { rows = found; selected.removeWhere((id) => !visible.contains(id)); scanning = false; });
    }
  }

  Future<void> _delete() async {
    if (scanning || deleting || selected.isEmpty) return;
    final ids = selected.toList();
    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('حذف پیام‌های انتخاب‌شده؟'),
      content: Text('${Jalali.digits(ids.length)} پیام برای همیشه از گوشی حذف می‌شود.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('انصراف')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حذف پیام‌ها'))]));
    if (!mounted || ok != true) return;
    setState(() => deleting = true);
    try {
      final remaining = ids.where(selected.contains).where((id) => !widget.store.starredIds.contains(id)).toList();
      for (var i = 0; i < remaining.length; i += 500) {
        final batch = remaining.sublist(i, (i + 500).clamp(0, remaining.length));
        if (!await widget.store.deleteMessages(batch) || !mounted) break;
        selected.removeAll(batch);
      }
    } finally { if (mounted) setState(() => deleting = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.kind.title)),
    body: SafeArea(child: Column(children: [
      if (widget.kind == CollectionKind.search) ...[
        Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .45),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: .16)),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Row(children: [
                Icon(Icons.manage_search_rounded, size: 25),
                SizedBox(width: 10),
                Expanded(child: Text('جست‌وجوی هوشمند در پیام‌های گوشی',
                  style: TextStyle(fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 7),
              Text('نام، شماره و متن را محلی جست‌وجو کنید؛ اطلاعات شما ارسال نمی‌شود.',
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                autofocus: false,
                textInputAction: TextInputAction.search,
                textAlign: TextAlign.right,
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(
                  hintText: 'نام، شماره یا متن پیام',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(17),
                    borderSide: BorderSide.none),
                ),
                onChanged: (value) { query = value; _schedule(); },
              ),
            ]),
          )),
        SizedBox(height: 54, child: ListView(scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), children: [
          FilterChip(label: const Text('لینک‌دار'), selected: linksOnly, onSelected: (v) { linksOnly = v; _schedule(); }),
          FilterChip(label: const Text('مبلغ‌دار'), selected: amountsOnly, onSelected: (v) { amountsOnly = v; _schedule(); }),
          ActionChip(label: Text(period == null ? 'بازهٔ تاریخ' : 'حذف بازهٔ تاریخ'), onPressed: () async {
            if (period != null) { period = null; _schedule(); return; }
            final range = await showDateRangePicker(context: context, firstDate: DateTime(1970), lastDate: DateTime.now());
            if (range != null && mounted) { period = range; _schedule(); }
          }),
          for (final c in MessageCategory.values)
            FilterChip(label: Text(categoryName(c)), selected: category == c,
              onSelected: (v) { category = v ? c : null; _schedule(); })
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 7), child: Row(children: [
          Icon(Icons.filter_alt_outlined, size: 18,
            color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 7),
          Expanded(child: Text(scanning ? 'در حال جست‌وجو…'
              : 'تعداد نتایج: ${Jalali.digits(rows.length)}',
              style: Theme.of(context).textTheme.labelLarge)),
          if (query.isNotEmpty || linksOnly || amountsOnly || category != null || period != null)
            TextButton.icon(onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              query = ''; linksOnly = false; amountsOnly = false;
              category = null; period = null;
              _schedule();
            }, icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('پاک‌سازی فیلترها')),
        ])),
      ],
      if (cleanup) Padding(padding: const EdgeInsets.all(12), child: Text(
        'کدهای تأیید قدیمی‌تر از یک روز و تبلیغات خوانده‌شدهٔ قدیمی‌تر از یک ماه را برای حذف انتخاب کنید.')),
      if (scanning) const LinearProgressIndicator(),
      if (!scanning && rows.isEmpty) Expanded(child: Center(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_rounded, size: 50,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .55)),
          const SizedBox(height: 12),
          const Text('نتیجه‌ای پیدا نشد. عبارت کوتاه‌تر یا فیلتر دیگری انتخاب کنید.',
            textAlign: TextAlign.center),
        ]))),
      if (rows.isNotEmpty) Expanded(child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        itemCount: rows.length, itemBuilder: (ctx, i) {
        final m = rows[i];
        final hide = widget.store.settings?.hidePreview == true;
        final preview = hide ? 'پیش‌نمایش پیام مخفی است' : BankPrivacy.preview(MessageLogic.category(m), m.body);
        final title = '${widget.store.displayName(m.sender)} · ${Jalali.short(m.date)}';
        final color = Theme.of(context).colorScheme;
        if (cleanup) { return Card(
          color: color.surfaceContainerLow,
          margin: const EdgeInsets.only(bottom: 7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          child: CheckboxListTile(value: selected.contains(m.id), title: Text(title),
          subtitle: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
          onChanged: deleting || scanning ? null : (v) => setState(() { if (v == true && m.id != null) { selected.add(m.id!); } else { selected.remove(m.id); } }))); }
        return Card(
          margin: const EdgeInsets.only(bottom: 7),
          color: color.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          leading: CircleAvatar(
            backgroundColor: color.primary.withValues(alpha: .10),
            child: Icon(switch (MessageLogic.category(m)) {
              MessageCategory.banking => Icons.account_balance_outlined,
              MessageCategory.personal => Icons.person_outline_rounded,
              MessageCategory.service => Icons.notifications_outlined,
              MessageCategory.advertising => Icons.campaign_outlined,
            }, color: color.primary, size: 20)),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 5),
            child: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(height: 1.65))),
          trailing: widget.kind == CollectionKind.starred && m.id != null ? IconButton(
            tooltip: 'برداشتن ستاره', icon: const Icon(Icons.star), onPressed: () => widget.store.toggleStar(m.id!)) : null,
          onTap: () => Navigator.push(ctx, MaterialPageRoute<void>(builder: (_) =>
            ConversationScreen(store: widget.store, address: m.sender, initialMessageId: m.id)))));
      })),
      if (cleanup) FilledButton.icon(onPressed: selected.isEmpty || scanning || deleting ? null : _delete,
        icon: const Icon(Icons.delete_outline), label: Text('حذف انتخاب‌شده‌ها (${Jalali.digits(selected.length)})'))
    ])));
}
