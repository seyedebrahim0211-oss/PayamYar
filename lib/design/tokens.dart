import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// پیام‌یار — سیستم طراحی ۳٫۱
///
/// یک منبع حقیقت برای رنگ، شعاع، فاصله، تایپ و سایه. هر صفحه‌ای که از این
/// توکن‌ها استفاده کند، خودکار با بقیه هماهنگ می‌ماند.
///
/// قاعدهٔ اصلی پک: طلایی روشن فقط تزئین است و هرگز متن نیست. هر طلایی که باید
/// خوانده شود از [goldInk] می‌آید. طلایی روشن روی کاغذ کنتراست ۱٫۳۴ دارد
/// (عملاً نامرئی) و [goldInk] با ۴٫۸۵ نسبت، AA را پاس می‌کند.
/// ─────────────────────────────────────────────────────────────────────────────

/// رنگ‌های پایه. روشن و تیره جدا نگه داشته شده‌اند تا هیچ صفحه‌ای مجبور نباشد
/// خودش `brightness == dark` را چک کند.
abstract final class SColor {
  // ── برند (ثابت در هر دو حالت) ──
  static const teal = Color(0xFF087F81);
  static const tealBright = Color(0xFF12A7A2);
  static const tealDeep = Color(0xFF05545A);
  static const tealNight = Color(0xFF08312F);

  /// طلایی تزئینی — فقط گرادیان، هایلایت شیشه و اسپارک. هرگز روی آن متن نگذارید.
  static const gold = Color(0xFFFFD27A);

  /// طلایی خوانا روی کاغذ روشن (کنتراست ۴٫۸۵ روی #FAF8F3).
  static const goldInk = Color(0xFF8F6612);

  /// طلایی خوانا روی سطح تیره (کنتراست ۱۰٫۳۸ روی #0B1E20).
  static const goldNight = Color(0xFFE7C57C);

  // ── سطح، روشن ──
  static const paper = Color(0xFFFAF8F3);
  static const paperSunken = Color(0xFFF2EEE4);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF08312F);
  static const inkMuted = Color(0xFF4A5F5C);
  static const line = Color(0xFFE2DCCC);

  // ── سطح، تیره ──
  static const paperNight = Color(0xFF0B1E20);
  static const surfaceNight = Color(0xFF13282B);
  static const inkNight = Color(0xFFE8F0EE);
  static const inkMutedNight = Color(0xFF9FB5B1);
  static const lineNight = Color(0xFF22403F);

  // ── معنایی (هر دو حالت) ──
  static const danger = Color(0xFFA33A2E);
  static const dangerNight = Color(0xFFE88A7C);
  static const success = Color(0xFF2F6B4F);
  static const successNight = Color(0xFF7FC49C);
  static const warning = Color(0xFF8A5A0B);
  static const warningNight = Color(0xFFE0A94A);

  /// رنگ آواتارها. هشت رنگ هم‌خانوادهٔ فیروزه‌ای/خاکی که در هر دو حالت کار می‌کنند.
  static const avatar = <Color>[
    Color(0xFF087F81), Color(0xFF305F91), Color(0xFF75539A), Color(0xFF9F5369),
    Color(0xFF47765F), Color(0xFFA17A37), Color(0xFFC0583B), Color(0xFF3A7CA5),
  ];

  /// رنگ متن روی آواتار — همیشه سفید، چون همهٔ رنگ‌های بالا تیره‌اند.
  static const onAvatar = Color(0xFFFFFFFF);
}

/// مقیاس شعاع. سلسله‌مراتب دارد: هرچه سطح بالاتر، شعاع بیشتر.
abstract final class SRadius {
  static const chip = 8.0;
  static const field = 12.0;
  static const tile = 16.0;
  static const card = 22.0;
  static const sheet = 28.0;
  static const pill = 999.0;

  /// آواتار مربع نرم — همان نسبتی که در آیکن لانچر استفاده شده.
  static Radius avatar(double size) => Radius.circular(size * .34);

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

/// مقیاس فاصله. گام ۴ پایه است.
abstract final class SSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  static const page = EdgeInsetsDirectional.fromSTEB(14, 0, 14, 0);
  static const card = EdgeInsets.all(lg);
  static const row = EdgeInsets.symmetric(horizontal: 10, vertical: 9);
}

/// مقیاس تایپوگرافی. نسبت ۱٫۲۵، با ارتفاع خط جداگانه برای فارسی.
abstract final class SType {
  static const display = 30.0;
  static const h1 = 23.0;
  static const h2 = 18.0;
  static const h3 = 15.5;
  static const body = 14.5;
  static const small = 12.5;
  static const micro = 11.0;

  /// حباب گفتگو پیش‌فرض؛ کاربر می‌تواند بین ۱۳ و ۲۰ تغییرش دهد.
  static const bubble = 15.5;
}

/// سایه‌ها. همه کم‌عمق و رنگی — سایهٔ خاکستری روی کاغذ کرم خاکی به نظر می‌رسد.
abstract final class SShadow {
  static List<BoxShadow> get card => [
        BoxShadow(color: SColor.tealNight.withValues(alpha: .06), blurRadius: 18, offset: const Offset(0, 6)),
      ];

  static List<BoxShadow> get raised => [
        BoxShadow(color: SColor.tealNight.withValues(alpha: .13), blurRadius: 26, spreadRadius: -6, offset: const Offset(0, 7)),
      ];

  static List<BoxShadow> get none => const [];
}

/// حرکت. همهٔ انیمیشن‌ها از این‌جا می‌آیند تا ریتم یکسان باشد.
abstract final class SMotion {
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 420);
}

/// سازندهٔ تم. تنها جایی که ThemeData ساخته می‌شود.
abstract final class STheme {
  static ThemeData build({
    required Brightness brightness,
    required Color seed,
    String? fontFamily,
    bool reduceEffects = false,
  }) {
    final dark = brightness == Brightness.dark;

    final paper = dark ? SColor.paperNight : SColor.paper;
    final surface = dark ? SColor.surfaceNight : SColor.surface;
    final ink = dark ? SColor.inkNight : SColor.ink;
    final inkMuted = dark ? SColor.inkMutedNight : SColor.inkMuted;
    final line = dark ? SColor.lineNight : SColor.line;

    // فیروزه‌ای برند پایهٔ طرح رنگ است؛ طلایی نقش سوم (tertiary) را می‌گیرد.
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness).copyWith(
      primary: dark ? SColor.tealBright : SColor.teal,
      onPrimary: Colors.white,
      primaryContainer: dark ? const Color(0xFF0F3B3D) : const Color(0xFFDCF1EE),
      onPrimaryContainer: dark ? const Color(0xFFB8E8E2) : SColor.tealDeep,
      // tertiary در روشن «طلایی خوانا» است، نه تزئینی — تا هرجا طراحی از رنگ سوم
      // استفاده کرد، متن قابل خواندن بماند.
      tertiary: dark ? SColor.goldNight : SColor.goldInk,
      onTertiary: dark ? SColor.tealNight : Colors.white,
      tertiaryContainer: dark ? const Color(0xFF4A3A14) : const Color(0xFFFCEBC4),
      onTertiaryContainer: dark ? const Color(0xFFFCEBC4) : const Color(0xFF3F2E05),
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: inkMuted,
      outline: dark ? const Color(0xFF2E514F) : const Color(0xFFC9C2B1),
      outlineVariant: line,
      error: dark ? SColor.dangerNight : SColor.danger,
      surfaceContainerLowest: paper,
      surfaceContainerLow: dark ? const Color(0xFF102326) : const Color(0xFFFDFBF6),
      surfaceContainer: dark ? const Color(0xFF16292C) : const Color(0xFFF7F4EC),
      surfaceContainerHigh: dark ? const Color(0xFF1A2F32) : const Color(0xFFF2EEE4),
      surfaceContainerHighest: dark ? const Color(0xFF1F3639) : const Color(0xFFECE7DA),
    );

    final base = dark ? Typography.material2021().white : Typography.material2021().black;
    TextStyle? fa(TextStyle? s, {double? size, FontWeight? weight, double height = 1.6}) => s?.copyWith(
          fontFamily: fontFamily, fontSize: size, fontWeight: weight, height: height, letterSpacing: 0,
        );

    final text = base.copyWith(
      headlineLarge: fa(base.headlineLarge, size: SType.display, weight: FontWeight.w900, height: 1.3),
      headlineSmall: fa(base.headlineSmall, size: SType.h1, weight: FontWeight.w800, height: 1.4),
      titleLarge: fa(base.titleLarge, size: SType.h2, weight: FontWeight.w800, height: 1.45),
      titleMedium: fa(base.titleMedium, size: SType.h3, weight: FontWeight.w700),
      titleSmall: fa(base.titleSmall, size: 14, weight: FontWeight.w700),
      bodyLarge: fa(base.bodyLarge, size: 16, height: 1.8),
      bodyMedium: fa(base.bodyMedium, size: SType.body, height: 1.75),
      bodySmall: fa(base.bodySmall, size: SType.small, height: 1.7),
      labelLarge: fa(base.labelLarge, size: 14, weight: FontWeight.w700),
      labelMedium: fa(base.labelMedium, size: SType.small, weight: FontWeight.w600),
      labelSmall: fa(base.labelSmall, size: SType.micro, weight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: paper,
      splashFactory: reduceEffects ? NoSplash.splashFactory : InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: 20, fontWeight: FontWeight.w900, color: ink, letterSpacing: 0),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: SRadius.all(SRadius.card)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(
          fontFamily: fontFamily, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        extendedTextStyle: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: SRadius.all(SRadius.tile)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.primary,
        secondarySelectedColor: scheme.primary,
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: SRadius.all(SRadius.pill)),
        labelStyle: TextStyle(fontFamily: fontFamily, fontSize: SType.small, fontWeight: FontWeight.w700, color: ink),
        secondaryLabelStyle: const TextStyle(fontSize: SType.small, fontWeight: FontWeight.w700, color: Colors.white),
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(SRadius.sheet)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: SRadius.all(SRadius.sheet)),
        titleTextStyle: TextStyle(fontFamily: fontFamily, fontSize: SType.h2, fontWeight: FontWeight.w800, color: ink),
        contentTextStyle: TextStyle(fontFamily: fontFamily, fontSize: SType.body, height: 1.8, color: ink),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(SRadius.tile))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(fontFamily: fontFamily, color: inkMuted),
        border: OutlineInputBorder(borderRadius: SRadius.all(SRadius.field), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: SRadius.all(SRadius.field), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: SRadius.all(SRadius.field),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: SRadius.all(SRadius.tile)),
          textStyle: TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: TextStyle(fontFamily: fontFamily, fontSize: SType.body, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: SRadius.all(SRadius.tile)),
          textStyle: TextStyle(fontFamily: fontFamily, fontSize: SType.body, fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: SRadius.all(SRadius.tile)),
        textStyle: TextStyle(fontFamily: fontFamily, fontSize: SType.body, color: ink),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : (dark ? SColor.inkMutedNight : SColor.surface)),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : (dark ? line : const Color(0xFFCFC9BA))),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: TextStyle(fontFamily: fontFamily, fontSize: SType.micro, color: Colors.white),
        decoration: BoxDecoration(
          color: dark ? SColor.tealNight : SColor.tealDeep,
          borderRadius: SRadius.all(SRadius.chip),
        ),
      ),
    );
  }
}
