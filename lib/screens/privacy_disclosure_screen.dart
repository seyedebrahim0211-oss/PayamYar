import 'package:flutter/material.dart';

/// In-app plain-language disclosure. This is not a substitute for the public,
/// hosted Privacy Policy and Data Safety declarations required by Google Play.
class PrivacyDisclosurePage extends StatelessWidget {
  const PrivacyDisclosurePage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const sections = <({String heading, String description, IconData icon})>[
      (heading: 'پیامک‌ها', icon: Icons.sms_outlined,
        description: 'اگر پیامیار را پیام‌رسان پیش‌فرض انتخاب کنید، برای نمایش، جستجو، ارسال و دریافت پیام به متن، فرستنده، گیرنده و زمان پیامک‌های گوشی دسترسی دارد. تحلیل پیشنهاد پاسخ و هشدار پیام مشکوک در خود گوشی انجام می‌شود.'),
      (heading: 'مخاطبین', icon: Icons.contacts_outlined,
        description: 'با اجازه شما، شماره، نام و در صورت نیاز تصویر مخاطب برای دفترچه تلفن، تشخیص نام فرستنده و گروه‌ها خوانده می‌شود. ویرایش یا حذف مخاطب با اقدام صریح شما انجام می‌شود.'),
      (heading: 'اعلان‌ها و حباب', icon: Icons.notifications_outlined,
        description: 'با اجازه اعلان، پیام جدید و در صورت انتخاب شما پیش‌نمایش متن نشان داده می‌شود. می‌توانید پیش‌نمایش را پنهان کنید. ممکن است اندروید برای حباب گفتگو دسترسی جداگانه بخواهد.'),
      (heading: 'اطلاعات مالی پیامک', icon: Icons.account_balance_wallet_outlined,
        description: 'اطلاعات تراکنش از متن پیامک بانکی روی گوشی استخراج و برای گزارش محلی استفاده می‌شود. نمایش مبلغ و پیش‌نمایش قابل مخفی‌سازی است.'),
      (heading: 'اینترنت و به‌روزرسانی', icon: Icons.system_update_outlined,
        description: 'نسخه وب‌سایتی پیامیار، برای بررسی به‌روزرسانی با honarmardomi.ir ارتباط می‌گیرد. برای نصب APK جدید، فقط با تأیید شما به نصب‌کننده اندروید ارجاع می‌دهد.'),
      (heading: 'پنل ملی‌پیامک (اختیاری)', icon: Icons.admin_panel_settings_outlined,
        description: 'اگر پنل مدیریتی را فعال کنید، نام کاربری و اطلاعات احراز هویت لازم برای وب‌سرویس ملی‌پیامک استفاده می‌شود و شماره‌ها و متن پیام‌هایی که از پنل ارسال می‌کنید به ارائه‌دهنده این سرویس منتقل می‌شوند. استفاده از این بخش اختیاری است.'),
      (heading: 'ذخیره و اختیار شما', icon: Icons.lock_outline_rounded,
        description: 'برچسب خانواده و گروه‌های محلی در حافظه برنامه ذخیره می‌شوند. با تغییر مجوزهای اندروید می‌توانید دسترسی‌ها را کنترل کنید. پاک‌کردن داده برنامه ممکن است تنظیمات و داده‌های محلی را حذف کند؛ پیامک‌های ذخیره‌شده در پایگاه پیامک سیستم ممکن است باقی بمانند.'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('حریم خصوصی پیامیار')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.verified_user_outlined, size: 30),
            const SizedBox(height: 8),
            Text('دسترسی‌ها دقیقاً چه کاری انجام می‌دهند؟',
              style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text('هیچ پیامکی بدون اقدام شما از دستیار هوشمند ارسال نمی‌شود. '
              'برای استفاده از SMS، پیامیار باید برنامه پیش‌فرض پیامک باشد. '
              'اجازه مخاطبین و اعلان را می‌توانید در تنظیمات گوشی لغو کنید.'),
          ]),
        ),
        const SizedBox(height: 12),
        for (final item in sections)
          Card(margin: const EdgeInsets.only(bottom: 9),
            child: Padding(padding: const EdgeInsets.all(14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(item.icon, color: scheme.primary),
                  const SizedBox(width: 9),
                  Expanded(child: Text(item.heading, style: Theme.of(context).textTheme.titleSmall))]),
                const SizedBox(height: 6),
                Text(item.description, style: Theme.of(context).textTheme.bodyMedium),
              ]))),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('این توضیحات داخل برنامه است. سیاست حریم خصوصی عمومی، نشانی تماس و فرم Data Safety فروشگاه باید جداگانه منتشر و با رفتار نسخه منتشرشده تطبیق داده شوند.'),
        ),
      ]),
    );
  }
}
