import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_store.dart';
import '../sms_bridge.dart';
import 'compose_tools.dart';
import 'conversation_screen.dart';

/// New message: recipient (typed or from contacts), ready-made texts, SIM choice. Draft is kept until sent.
class ComposeScreen extends StatefulWidget {
  final AppStore store;
  final String? initialTo;
  final String? initialBody;
  const ComposeScreen({super.key, required this.store, this.initialTo, this.initialBody});
  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final to = TextEditingController();
  final body = TextEditingController();
  bool sending = false;
  AppStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    final hasInitial = widget.initialTo != null || widget.initialBody != null;
    to.text = hasInitial ? widget.initialTo ?? '' : p.getString('draft_to') ?? '';
    body.text = hasInitial ? widget.initialBody ?? '' : p.getString('draft_body') ?? '';
    setState(() {});
  }

  Future<void> _saveDraft() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('draft_to', to.text);
    await p.setString('draft_body', body.text);
  }

  @override
  void dispose() {
    to.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    try {
      final value = await SmsBridge.pickContact();
      if (value != null && mounted) {
        to.text = value;
        await _saveDraft();
      }
    } catch (_) {
      store.onNotice?.call('دفترچه مخاطبان در دسترس نیست.');
    }
  }

  Future<void> _send() async {
    final target = to.text.trim();
    final text = body.text.trim();
    if (target.isEmpty || text.isEmpty) {
      store.onNotice?.call('شماره گیرنده و متن پیام را وارد کنید.');
      return;
    }
    setState(() => sending = true);
    final pending = await store.send(target, text);
    if (!mounted) return;
    setState(() => sending = false);
    if (pending == null && store.android) return;
    to.clear();
    body.clear();
    await _saveDraft();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ConversationScreen(store: store, address: target)));
    if (pending != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          content: const Text('پیام تا ۵ ثانیه دیگر ارسال می‌شود'),
          action: SnackBarAction(label: 'لغو', onPressed: () => store.undo(pending))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('پیام جدید')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        TextField(
          controller: to,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.phone,
          onChanged: (_) => _saveDraft(),
          decoration: InputDecoration(
            labelText: 'شماره گیرنده',
            prefixIcon: const Icon(Icons.person_outline_rounded),
            suffixIcon: SmsBridge.supported
                ? IconButton(tooltip: 'انتخاب از مخاطبان', icon: const Icon(Icons.contacts_rounded), onPressed: _pickContact)
                : null),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: body,
          onChanged: (_) {
            _saveDraft();
            setState(() {});
          },
          maxLength: 2000,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(labelText: 'متن پیام', alignLabelWithHint: true, counterText: ''),
        ),
        Row(children: [
          Expanded(child: SmsCounter(text: body.text)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(Icons.bolt_rounded),
            label: const Text('پیام‌های آماده'),
            onPressed: () async {
              final text = await showTemplatesSheet(context, store, currentText: body.text);
              if (text == null || !mounted) return;
              setState(() => body.text = text);
              await _saveDraft();
            })),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(
            icon: const Icon(Icons.auto_fix_high_rounded),
            label: const Text('ویرایش متن'),
            onPressed: body.text.trim().isEmpty ? null : () async {
              final text = await showPolishSheet(context, body.text);
              if (text == null || !mounted) return;
              setState(() => body.text = text);
              await _saveDraft();
            })),
        ]),
        const SizedBox(height: 16),
        if (store.sims.length > 2) ...[
          DropdownButtonFormField<int>(
            initialValue: store.selectedSim,
            decoration: const InputDecoration(labelText: 'سیم‌کارت ارسال', prefixIcon: Icon(Icons.sim_card_outlined)),
            items: [
              for (final s in store.sims)
                DropdownMenuItem<int>(value: s['id'] as int, child: Text(s['label'].toString())),
            ],
            onChanged: (v) => store.selectedSim = v ?? -1,
          ),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: sending ? null : _send,
          icon: const Icon(Icons.send_rounded, textDirection: TextDirection.ltr),
          label: const Text('ارسال'),
        ),
        const SizedBox(height: 8),
        Text('تا ۵ ثانیه پس از ارسال می‌توانید آن را لغو کنید.', textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
      ]),
    );
  }
}
