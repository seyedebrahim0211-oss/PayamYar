/// On-device reply suggestions. Never auto-sends or uploads SMS content.
/// Recommendations are intentionally conservative and require an explicit send.
class SmartAssistant {
  static List<String> suggestReplies(String incoming) {
    final value = incoming.trim().toLowerCase();
    if (value.isEmpty) return const [];
    if (value.contains('سلام') || value.contains('درود')) {
      return const ['سلام، وقت شما بخیر 🌷', 'سلام، خوشحالم از پیامتان', 'سلام، در خدمتم'];
    }
    if (value.contains('ممنون') || value.contains('مرسی') || value.contains('تشکر')) {
      return const ['خواهش می‌کنم 🌹', 'لطف دارید', 'انجام وظیفه بود'];
    }
    if (value.contains('جلسه') || value.contains('ساعت') || value.contains('قرار')) {
      return const ['زمان را تأیید می‌کنم', 'ممنون، هماهنگ می‌کنم', 'اجازه بدهید بررسی کنم'];
    }
    if (value.contains('کجا') || value.contains('آدرس') || value.contains('موقعیت')) {
      return const ['موقعیت را برایتان می‌فرستم', 'تا چند دقیقه دیگر خبر می‌دهم', 'لطفاً موقعیت دقیق را بفرستید'];
    }
    if (value.contains('؟') || value.contains('?')) {
      return const ['الان بررسی می‌کنم', 'کمی بعد اطلاع می‌دهم', 'لطفاً بیشتر توضیح دهید'];
    }
    return const [];
  }
}
