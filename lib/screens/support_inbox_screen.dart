import 'dart:async';
import 'package:flutter/material.dart';
import '../jalali.dart';
import '../support_service.dart';

/// Only ticket IDs appear in the list. Contents are fetched with Keystore
/// credentials when the user explicitly opens that conversation.
class SupportInboxScreen extends StatefulWidget {
  const SupportInboxScreen({super.key});
  @override
  State<SupportInboxScreen> createState() => _SupportInboxScreenState();
}

class _SupportInboxScreenState extends State<SupportInboxScreen> {
  late Future<List<int>> _ids = SupportService.savedIds();
  void _refresh() => setState(() => _ids = SupportService.savedIds());
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('پیگیری گزارش‌ها'),
      actions: [IconButton(onPressed: _refresh, tooltip: 'تازه‌سازی',
        icon: const Icon(Icons.refresh_rounded))]),
    body: FutureBuilder<List<int>>(
      future: _ids,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final ids = snapshot.data!;
        if (ids.isEmpty) return const Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('هنوز گزارشی ثبت نشده است. گزارش خرابی را از تنظیمات ارسال کنید.')));
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: ids.length,
          itemBuilder: (context, index) {
            final id = ids[index];
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.support_agent_rounded)),
              title: Text('درخواست شماره ${Jalali.digits(id)}'),
              subtitle: const Text('برای مشاهده پاسخ پشتیبانی لمس کنید'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SupportThreadScreen(ticketId: id))),
            ));
          },
        );
      },
    ),
  );
}

class SupportThreadScreen extends StatefulWidget {
  final int ticketId;
  const SupportThreadScreen({super.key, required this.ticketId});
  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}
class _SupportThreadScreenState extends State<SupportThreadScreen> {
  final _reply = TextEditingController();
  late Future<SupportTicket> _ticket;
  Timer? _check;
  bool _sending = false;
  @override
  void initState() {
    super.initState();
    _ticket = SupportService.detail(widget.ticketId);
    _check = Timer.periodic(const Duration(seconds: 45), (_) {
      if (mounted && !_sending) _refresh();
    });
  }
  void _refresh() => setState(() => _ticket = SupportService.detail(widget.ticketId));
  @override
  void dispose() {
    _check?.cancel();
    _reply.dispose();
    super.dispose();
  }
  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.length < 2 || _sending) return;
    setState(() => _sending = true);
    try {
      final updated = await SupportService.respond(widget.ticketId, text);
      if (!mounted) return;
      _reply.clear();
      setState(() => _ticket = Future.value(updated));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ارسال پاسخ ممکن نبود؛ اینترنت و اتصال را بررسی کنید.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('پشتیبانی • ${Jalali.digits(widget.ticketId)}'),
        actions: [IconButton(onPressed: _refresh, tooltip: 'بررسی پاسخ جدید',
          icon: const Icon(Icons.refresh_rounded))]),
      body: Column(children: [
        Expanded(child: FutureBuilder<SupportTicket>(
          future: _ticket,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Center(child: TextButton.icon(onPressed: _refresh,
                icon: const Icon(Icons.refresh), label: const Text('بازخوانی تیکت ممکن نبود؛ تلاش دوباره')));
            }
            final ticket = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(child: ListTile(
                  title: Text(ticket.subject, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(ticket.status == 'answered' ? 'پشتیبانی پاسخ داده است' : 'در صف بررسی'),
                  leading: const Icon(Icons.verified_user_outlined),
                )),
                for (final entry in ticket.entries)
                  Align(
                    alignment: entry.role == 'admin' ? Alignment.centerLeft : Alignment.centerRight,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 340),
                      child: Card(
                        color: entry.role == 'admin' ? theme.colorScheme.secondaryContainer
                            : theme.colorScheme.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(entry.role == 'admin' ? 'پشتیبانی پیام‌یار' : 'شما',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            SelectableText(entry.body),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        )),
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: TextField(
              controller: _reply, maxLines: 3, minLines: 1,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: 'پیام برای پشتیبانی…', counterText: '',
                border: OutlineInputBorder()),
            )),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _sending ? null : _send,
              tooltip: 'ارسال پاسخ',
              icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded)),
          ]),
        )),
      ]),
    );
  }
}
