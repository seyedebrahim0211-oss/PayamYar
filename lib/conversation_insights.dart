import 'message_logic.dart';

/// Explainable, offline conversation tools. No network, automatic responses,
/// or personal-message logging. This is rules-based assistance, not an LLM.
class ConversationInsights {
  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  static const _taskCues = ['لطفاً', 'لطفا', 'بفرست', 'ارسال کن', 'یادت', 'فراموش نکن',
    'پیگیری', 'انجام بده', 'تماس بگیر', 'پرداخت کن', 'قرار', 'جلسه', 'مدرک'];
  static const _moneyCues = ['رمز', 'cvv', 'شماره کارت', 'واریز کن', 'انتقال وجه',
    'کارت به کارت', 'پرداخت فوری', 'لینک پرداخت'];

  /// Summary consists only of short extracts from existing received messages.
  /// Limit inputs to protect the UI from large imported conversations.
  static String summarize(List<MessageRecord> messages) {
    final incoming = messages.where((m) => !m.outgoing && m.body.trim().isNotEmpty).take(30).toList();
    if (incoming.isEmpty) return 'پیام دریافتی برای خلاصه‌سازی وجود ندارد.';
    final excerpts = incoming.take(3).map((m) {
      final t = _clean(m.body);
      return '• ${t.length > 140 ? '${t.substring(0, 140)}…' : t}';
    }).join('\n');
    return 'گزیده سه پیام دریافتی اخیر (خلاصه‌سازی آفلاین):\n$excerpts';
  }

  static List<String> actionItems(List<MessageRecord> messages) {
    final out = <String>[];
    for (final msg in messages.where((m) => !m.outgoing).take(40)) {
      final t = _clean(msg.body);
      final lower = t.toLowerCase();
      if (!_taskCues.any(lower.contains)) continue;
      // Do not turn suspected payment scams or OTP requests into tasks.
      if (_moneyCues.any(lower.contains) || MessageLogic.risk(t, sender: msg.sender).suspicious) continue;
      final value = t.length > 125 ? '${t.substring(0, 125)}…' : t;
      if (!out.contains(value)) out.add(value);
      if (out.length == 5) break;
    }
    return out;
  }

  static List<String> securityWarnings(List<MessageRecord> messages) {
    final out = <String>[];
    for (final msg in messages.where((m) => !m.outgoing).take(40)) {
      final risk = MessageLogic.risk(msg.body, sender: msg.sender);
      if (!risk.suspicious) continue;
      for (final reason in risk.reasons) {
        if (!out.contains(reason)) out.add(reason);
      }
      if (out.length >= 5) break;
    }
    return out.take(5).toList();
  }
}
