import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WhatsNewCard extends StatefulWidget {
  const WhatsNewCard({super.key});
  @override
  State<WhatsNewCard> createState() => _WhatsNewCardState();
}
class _WhatsNewCardState extends State<WhatsNewCard> {
  String? marker;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = '${info.version}+${info.buildNumber}';
      final prefs = await SharedPreferences.getInstance();
      if (mounted && prefs.getString('dismissed_news') != version) setState(() => marker = version);
    } catch (_) { /* Package info can be unavailable on preview platforms. */ }
  }
  @override
  Widget build(BuildContext context) => marker == null ? const SizedBox.shrink() :
    Card(margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5), child: ListTile(
      leading: const Icon(Icons.new_releases_outlined), title: const Text('تازه‌های پیام‌یار'),
      subtitle: const Text('جست‌وجوی پیشرفته، کدهای تأیید، پیام‌های ستاره‌دار و پاک‌سازی با تأیید شما در صندوق پیام‌ها قرار دارند. در گفتگوها می‌توانید پیام را نقل‌قول کنید، سکوت را تنظیم کنید و پیش‌نویس خود را نگه دارید. ویجت و میانبر پیام جدید نیز به اندروید اضافه شده‌اند.', maxLines: 5),
      trailing: IconButton(tooltip: 'بستن تازه‌ها', icon: const Icon(Icons.close), onPressed: () async {
        final version = marker!;
        setState(() => marker = null);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('dismissed_news', version);
      })));
}
