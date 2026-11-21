import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// ایزوله‌سازی دوجهته (bidi)
///
/// در متن فارسی، رشته‌های لاتین و عددی جابه‌جا نمایش داده می‌شوند:
///
///   «کد 12345ABC را وارد کنید»  → ممکن است «ABC12345» دیده شود
///   «#FFD27A»                   → «FFD27A#» دیده می‌شود
///   «۰۹۱۲…۴۵۶۷»                 → «۴۵۶۷…۰۹۱۲» دیده می‌شود
///
/// چون الگوریتم دوجهتهٔ یونیکد، ترتیب بصری بخش‌های عددی/لاتین داخل متن راست‌به‌چپ
/// را خودش تعیین می‌کند. راه‌حل استاندارد، محاصرهٔ آن رشته با FSI (U+2068) و
/// PDI (U+2069) است.
///
/// استفاده:
///   Text('کد ${Bidi.isolate(code)} را وارد کنید')
///   BidiText('09121234567')
/// ─────────────────────────────────────────────────────────────────────────────
abstract final class Bidi {
  static const _fsi = '\u2068'; // First Strong Isolate
  static const _pdi = '\u2069'; // Pop Directional Isolate

  /// رشته را داخل محاصرهٔ دوجهته می‌گذارد. اگر رشته خالی باشد، دست‌نخورده برمی‌گردد
  /// تا متن‌های خالی کاراکتر نامرئی اضافه نگیرند.
  static String isolate(String value) {
    if (value.isEmpty) return value;
    // اگر از قبل محاصره شده، دوباره نمی‌پیچیم.
    if (value.startsWith(_fsi) && value.endsWith(_pdi)) return value;
    return '$_fsi$value$_pdi';
  }

  /// آیا این رشته چیزی دارد که به محاصره نیاز داشته باشد؟ عدد، لاتین یا نماد.
  static bool needs(String value) {
    for (final rune in value.runes) {
      final latin = (rune >= 0x30 && rune <= 0x39) || // 0-9
          (rune >= 0x41 && rune <= 0x5A) || // A-Z
          (rune >= 0x61 && rune <= 0x7A) || // a-z
          (rune >= 0x0660 && rune <= 0x0669) || // ارقام عربی
          (rune >= 0x06F0 && rune <= 0x06F9) || // ارقام فارسی
          rune == 0x23 || // #
          rune == 0x40 || // @
          rune == 0x2B || // +
          rune == 0x2D; // -
      if (latin) return true;
    }
    return false;
  }

  /// فقط وقتی لازم است محاصره می‌کند — برای متن‌های کاملاً فارسی، رشتهٔ اصلی
  /// برمی‌گردد تا هیچ کاراکتر نامرئی وارد UI نشود.
  static String smart(String value) => needs(value) ? isolate(value) : value;
}

/// متنی که خودش را در برابر جابه‌جایی دوجهته محافظت می‌کند.
///
/// برای شماره تلفن، کد تأیید، آدرس، کد رهگیری، مبلغ و هر رشتهٔ لاتین/عددی که
/// داخل جملهٔ فارسی می‌نشیند.
class BidiText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextDirection? textDirection;

  const BidiText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.textDirection,
  });

  @override
  Widget build(BuildContext context) => Text(
        Bidi.isolate(text),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        // جهت پایه راست‌به‌چپ است؛ محاصره فقط ترتیب داخلی را درست می‌کند.
        textDirection: textDirection ?? TextDirection.rtl,
      );
}

/// مبلغ فارسی با ارقام فارسی و جداکنندهٔ هزارگان، به‌صورت محاصره‌شده.
/// «۲٬۵۰۰٬۰۰۰» — داخل جملهٔ فارسی جابه‌جا نمی‌شود.
String moneyText(int toman) {
  final digits = toman.abs().toString().split('').reversed.toList();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && i % 3 == 0) out.write('٬');
    out.write(digits[i]);
  }
  final grouped = out.toString().split('').reversed.join();
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final persian = grouped.split('').map((c) {
    final n = int.tryParse(c);
    return n == null ? c : fa[n];
  }).join();
  return Bidi.isolate(toman < 0 ? '−$persian' : persian);
}
