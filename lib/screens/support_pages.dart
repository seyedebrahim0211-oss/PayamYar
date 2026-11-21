import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../app_settings.dart';
import '../app_store.dart';
import '../brand_mark.dart';
import '../jalali.dart';
import '../sms_bridge.dart';
import '../update_service.dart';
import '../support_service.dart';
import 'support_inbox_screen.dart';

const _faq = <(String, String)>[
  ('چرا باید پیام‌یار را پیام‌رسان پیش‌فرض کنم؟',
    'اندروید فقط به پیام‌رسان پیش‌فرض اجازه می‌دهد پیامک‌های جدید را دریافت، ذخیره، حذف یا علامت «خوانده‌شده» بزند. بدون آن، پیام‌یار فقط پیام‌ها را نمایش می‌دهد.'),
  ('پیام‌های جدید دیر می‌رسند یا اعلان نمی‌آید، چه کنم؟',
    'از «تنظیمات ← حریم خصوصی و امنیت ← دسترسی‌های ویژه» بهینه‌سازی باتری را برای پیام‌یار خاموش و اعلان‌ها را روشن کنید. در برخی گوشی‌ها (شیائومی، هواوی، سامسونگ) باید «اجرای خودکار» را هم فعال کنید.'),
  ('حلقه دور دکمه ارسال چیست؟',
    'فرصت لغو است. تا وقتی حلقه کامل نشده، با لمس ✕ روی همان دکمه پیام ارسال نمی‌شود و متن به کادر نوشتن برمی‌گردد. مدت آن را در «پیامک و ارسال» از ۱ تا ۱۰ ثانیه تنظیم یا خاموش کنید.'),
  ('«ارسال شد» با «تحویل شد» چه فرقی دارد؟',
    '«ارسال شد» یعنی شبکه اپراتور پیامک را پذیرفته است. «تحویل شد» (دو تیک آبی) فقط وقتی نمایش داده می‌شود که گزارش تحویل از گوشی گیرنده برسد؛ همه اپراتورها این گزارش را نمی‌فرستند.'),
  ('صدای ارسال را چطور تغییر دهم؟',
    'در «پیامک و ارسال ← تأیید ارسال» بین صدای کوتاه، اعلان یا بی‌صدا انتخاب کنید. در حالت بی‌صدا یا لرزش گوشی و ساعت سکوت، صدایی پخش نمی‌شود.'),
  ('چطور پیام را در زمان مشخص بفرستم؟',
    'دکمه ارسال را نگه دارید یا از منوی + گزینه «ارسال زمان‌دار» را بزنید و روز و ساعت را انتخاب کنید (تا ۳۰ روز آینده).'),
  ('قالب گفتگو و اندازه متن را چطور عوض کنم؟',
    'در صفحه گفتگو از منوی ⋮ «قالب گفتگو» یا در «تنظیمات ← ظاهر و قالب گفتگو» یکی از قالب‌های سنتی، شیشه‌ای، مینیمال یا کلاسیک را انتخاب کنید.'),
  ('پیام کد تأیید را چطور سریع کپی کنم؟',
    'کنار پیام‌های دارای کد تأیید و در اعلان آن‌ها دکمه «کپی کد» نمایش داده می‌شود.'),
  ('به‌روزرسانی چطور انجام می‌شود؟ امن است؟',
    'نسخه جدید فقط از honarmardomi.ir دریافت می‌شود؛ اثر انگشت فایل و امضای رسمی پیام‌یار پیش از نصب بررسی و نصب با تأیید خودتان در نصب‌کننده اندروید انجام می‌شود. داده‌های شما حفظ می‌شود.'),
  ('آیا پیامک‌های من جایی ارسال می‌شود؟',
    'متن پیامک‌ها و فهرست مخاطبان برای پشتیبانی ارسال نمی‌شود. فقط متن گزارشی که خودتان ثبت و ارسال می‌کنید، به‌صورت امن در سامانه پشتیبانی honarmardomi.ir ذخیره می‌شود؛ بررسی به‌روزرسانی و سرویس‌های اختیاری ممکن است به اینترنت نیاز داشته باشند.'),
  ('پیام چندرسانه‌ای (MMS) پشتیبانی می‌شود؟',
    'فعلاً خیر؛ پیام‌یار اعلان MMS را نشان می‌دهد ولی دانلود آن را انجام نمی‌دهد.'),
  ('پیش از تعویض گوشی یا نصب دوباره چه کنم؟',
    'از «تنظیمات ← پشتیبان تنظیمات» نسخه پشتیبان را برای خودتان بفرستید. پیامک‌ها در حافظه خود اندروید می‌مانند.'),
];

class FaqPage extends StatefulWidget {
  const FaqPage({super.key});
  @override
  State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _faq.where((e) => query.isEmpty || e.$1.contains(query) || e.$2.contains(query)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('سوالات متداول')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        TextField(
          onChanged: (v) => setState(() => query = v.trim()),
          decoration: InputDecoration(hintText: 'جستجو در پرسش‌ها', isDense: true,
            prefixIcon: const Icon(Icons.search_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none)),
        ),
        const SizedBox(height: 12),
        for (final (q, a) in items)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              shape: const Border(),
              leading: Icon(Icons.help_outline_rounded, color: scheme.primary),
              title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [Text(a, style: const TextStyle(height: 1.9))],
            ),
          ),
        if (items.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('پرسشی پیدا نشد؛ از «گزارش خرابی» با ما در میان بگذارید.',
            textAlign: TextAlign.center)),
      ]),
    );
  }
}

class BugReportPage extends StatefulWidget {
  final AppStore store;
  final AppSettings settings;
  const BugReportPage({super.key, required this.store, required this.settings});
  @override
  State<BugReportPage> createState() => _BugReportPageState();
}

class _BugReportPageState extends State<BugReportPage> {
  final what = TextEditingController();
  final steps = TextEditingController();
  String kind = 'ارسال پیام';
  bool includeInfo = true;
  bool _sending = false;
  static const kinds = ['ارسال پیام', 'دریافت پیام', 'اعلان و صدا', 'ظاهر برنامه', 'به‌روزرسانی', 'سایر'];

  @override
  void dispose() {
    what.dispose();
    steps.dispose();
    super.dispose();
  }

  Future<String> _report() async {
    final info = await PackageInfo.fromPlatform();
    final s = widget.store;
    final buffer = StringBuffer()
      ..writeln('گزارش خرابی پیام‌یار')
      ..writeln('بخش: $kind')
      ..writeln('شرح: ${what.text.trim()}');
    if (steps.text.trim().isNotEmpty) buffer.writeln('مراحل تکرار: ${steps.text.trim()}');
    if (includeInfo) {
      buffer
        ..writeln('—')
        ..writeln('نسخه: ${info.version} (${info.buildNumber})')
        ..writeln('سیستم: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}')
        ..writeln('پیش‌فرض: ${s.isDefault ? 'بله' : 'خیر'} • دسترسی ویژه کامل: ${s.access.complete ? 'بله' : 'خیر'}')
        ..writeln('تأخیر ارسال: ${widget.settings.sendDelayEnabled ? widget.settings.sendDelaySeconds : 0}s • قالب: ${widget.settings.chatStyle.name}');
    }
    return buffer.toString();
  }

  Future<void> _send() async {
    if (what.text.trim().length < 5 || _sending) {
      widget.store.onNotice?.call('لطفاً مشکل را دقیق‌تر توضیح دهید.');
      return;
    }
    setState(() => _sending = true);
    try {
      final text = await _report();
      final info = await PackageInfo.fromPlatform();
      const categories = {
        'ارسال پیام': 'delivery', 'دریافت پیام': 'delivery',
        'اعلان و صدا': 'notification', 'ظاهر برنامه': 'bug',
        'به‌روزرسانی': 'bug', 'سایر': 'other',
      };
      final id = await SupportService.create(
        category: categories[kind] ?? 'other',
        subject: '$kind — ${what.text.trim().length > 70 ? what.text.trim().substring(0, 70) : what.text.trim()}',
        body: text, version: info.version);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => SupportThreadScreen(ticketId: id)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ثبت گزارش ممکن نشد؛ اتصال اینترنت را بررسی کنید. اطلاعات گزارش در کادرها باقی می‌ماند.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش خرابی')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        Text('کدام بخش مشکل دارد؟', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final k in kinds) ChoiceChip(label: Text(k), selected: kind == k, onSelected: (_) => setState(() => kind = k)),
        ]),
        const SizedBox(height: 16),
        TextField(controller: what, minLines: 3, maxLines: 6, maxLength: 1000,
          decoration: const InputDecoration(labelText: 'چه اتفاقی افتاد؟', alignLabelWithHint: true,
            hintText: 'مثلاً: بعد از ارسال، پیام دو بار در گفتگو دیده می‌شود')),
        const SizedBox(height: 8),
        TextField(controller: steps, minLines: 2, maxLines: 4, maxLength: 600,
          decoration: const InputDecoration(labelText: 'چطور تکرار می‌شود؟ (اختیاری)', alignLabelWithHint: true)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('افزودن اطلاعات فنی'),
          subtitle: const Text('نسخه برنامه، نسخه اندروید و وضعیت دسترسی‌ها — بدون متن پیام یا شماره‌ها'),
          value: includeInfo, onChanged: (v) => setState(() => includeInfo = v)),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _sending ? null : _send,
          icon: const Icon(Icons.send_rounded), label: Text(_sending ? 'در حال ثبت امن گزارش…' : 'ثبت در پشتیبانی هنر مردمی')),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.forum_outlined),
          label: const Text('پیگیری گزارش‌ها و پاسخ مدیر'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const SupportInboxScreen())),
        ),
        const SizedBox(height: 10),
        Text('فقط متن همین فرم با تأیید ارسال به سامانه پشتیبانی سایت منتقل می‌شود؛ شماره مدیر نمایش داده نمی‌شود و متن SMSهای گوشی ارسال نخواهد شد.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap) => Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(leading: Icon(icon, color: scheme.primary), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(sub), trailing: const Icon(Icons.chevron_left_rounded), onTap: onTap));
    return Scaffold(
      appBar: AppBar(title: const Text('ارتباط با ما')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Center(child: PayamYarLogotype(height: 46, tagline: true))),
        tile(Icons.language_rounded, 'وب‌سایت هنر مردمی', 'honarmardomi.ir',
          () => UpdateService.openDownload('https://honarmardomi.ir/')),
        tile(Icons.phone_android_rounded, 'صفحه رسمی پیام‌یار', 'دانلود و اخبار نسخه‌ها',
          () => UpdateService.openDownload('https://honarmardomi.ir/payamyar/')),
        tile(Icons.share_rounded, 'معرفی پیام‌یار به دوستان', 'ارسال لینک دانلود',
          () => SmsBridge.shareText('پیام‌یار؛ پیام‌رسان پیامکی فارسی و امن\nدانلود: https://honarmardomi.ir/payamyar/',
            subject: 'پیام‌یار', title: 'معرفی پیام‌یار')),
      ]),
    );
  }
}

class AboutPage extends StatelessWidget {
  final Future<PackageInfo> packageInfo;
  const AboutPage({super.key, required this.packageInfo});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('درباره پیام‌یار')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
        const Center(child: PayamYarLogotype(height: 60, tagline: true)),
        const SizedBox(height: 18),
        FutureBuilder<PackageInfo>(future: packageInfo, builder: (context, snap) => Center(child: Text(
          snap.hasData ? 'نسخه ${Jalali.digits(snap.data!.version)} (ساخت ${Jalali.digits(snap.data!.buildNumber)})' : '',
          style: TextStyle(color: scheme.onSurfaceVariant)))),
        const SizedBox(height: 18),
        const Text('پیام‌یار پیام‌رسان پیامکی فارسی از خانواده هنر مردمی است: گفتگوهای مرتب، جداسازی پیام‌های بانکی و تبلیغاتی، '
          'گزارش مالی، گروه‌های پیامکی، ارسال زمان‌دار، فرصت لغو و قالب‌های زیبای گفتگو. '
          'همه پیام‌ها فقط روی گوشی شما نگه‌داری می‌شود.', style: TextStyle(height: 1.95)),
        const SizedBox(height: 18),
        Text('قلم: وزیرمتن (SIL Open Font License)', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}
