import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_store.dart';
import '../sms_bridge.dart';
import 'compose_screen.dart';
import 'contact_picker.dart';

/// Invitations are always user initiated. No messages are sent from this page.
class InviteFriendsScreen extends StatefulWidget {
  final AppStore store;
  const InviteFriendsScreen({super.key, required this.store});

  @override
  State<InviteFriendsScreen> createState() => _InviteFriendsScreenState();
}

class _InviteFriendsScreenState extends State<InviteFriendsScreen> {
  static const link = 'https://honarmardomi.ir/payamyar/';
  static const invitation =
      'سلام! من از پیام‌یار برای مدیریت پیامک‌ها استفاده می‌کنم. '
      'اگر دوست داشتی، از اینجا با امکاناتش آشنا شو و دانلودش کن:\n$link';
  bool picking = false;

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _inviteBySms() async {
    if (picking) return;
    setState(() => picking = true);
    try {
      final names = <Map<String, String>>[];
      if (widget.store.permissions.contacts) {
        try {
          for (final item in await SmsBridge.listContacts()) {
            final number = SmsBridge.normalizeNumber(item['number'] ?? '');
            if (RegExp(r'^\+?[0-9]{7,15}$').hasMatch(number)) {
              names.add({'name': item['name'] ?? '', 'number': number});
            }
          }
        } catch (_) {
          // Manual recipient entry remains available if the provider fails.
        }
      }
      if (!mounted) return;
      if (names.isEmpty) {
        _openComposer(const []);
        return;
      }
      final selected = await showContactPicker(
        context, contacts: names, selected: <String>{}, maxSelection: 10,
      );
      if (!mounted || selected == null || selected.isEmpty) return;
      _openComposer(selected.toList());
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  void _openComposer(List<String> recipients) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ComposeScreen(
        store: widget.store, initialRecipients: recipients, initialBody: invitation,
      ),
    ));
  }

  Future<void> _share() async {
    try {
      if (await SmsBridge.shareText(invitation,
          subject: 'دعوت به پیام‌یار', title: 'معرفی پیام‌یار به دوستان')) {
        return;
      }
    } catch (_) {}
    await Clipboard.setData(const ClipboardData(text: invitation));
    _notice('متن دعوت کپی شد. می‌توانید برای دوستان بفرستید.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('معرفی به دوستان')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF087F81), Color(0xFF07585F)],
              begin: Alignment.topRight, end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(children: [
            const CircleAvatar(radius: 34,
              backgroundColor: Color(0x22FFFFFF),
              child: Icon(Icons.favorite_rounded, size: 36, color: Colors.white)),
            const SizedBox(height: 16),
            const Text('پیام‌یار را به دوستانت معرفی کن',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text('یک پیام‌رسان فارسی برای پیامک‌های گوشی؛ '
                'سریع، خوانا و با هویت ایرانی',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFE5F3EE), height: 1.8)),
          ]),
        ),
        const SizedBox(height: 20),
        Text('متن دعوت', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: SelectableText(invitation, style: const TextStyle(height: 1.85)),
          ),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: picking ? null : _inviteBySms,
          icon: picking ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.sms_rounded),
          label: const Text('دعوت با پیامک'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _share,
          icon: const Icon(Icons.ios_share_rounded),
          label: const Text('اشتراک‌گذاری در برنامه‌های دیگر'),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: link));
            _notice('لینک دانلود کپی شد.');
          },
          icon: const Icon(Icons.link_rounded),
          label: const Text('کپی لینک دانلود'),
        ),
        const SizedBox(height: 10),
        Text('پیامک فقط پس از انتخاب گیرنده و تأیید شما در صفحه ارسال می‌شود. '
          'مخاطبین به سرور ارسال نمی‌شوند.',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.7),
          textAlign: TextAlign.center),
      ]),
    );
  }
}
