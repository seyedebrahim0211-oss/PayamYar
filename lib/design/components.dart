import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// کارت هوشمند
///
/// قاعدهٔ چهارم پک: هوش باید دیده شود، نه ادعا. هر قابلیت هوشمند باید بگوید
/// «چرا» — «از پیام مادر استخراج شد»، «سه ماه پیاپی». بدون دلیل، کاربر به
/// تشخیص اعتماد نمی‌کند و خاموشش می‌کند.
///
/// این ویجت جای تکرار همان جعبهٔ گرادیانی در چند صفحه است.
/// ─────────────────────────────────────────────────────────────────────────────
class SmartCard extends StatelessWidget {
  final IconData icon;
  final String title;

  /// دلیل یا توضیح — یک جملهٔ کوتاه، نه پاراگراف.
  final String reason;

  /// اقدام اختیاری، مثل «یادآوری بگذار».
  final String? actionLabel;
  final VoidCallback? onAction;

  /// رنگ تأکید. پیش‌فرض فیروزەی برند.
  final Color? accent;

  /// کارت هشدار (کلاهبرداری، مبلغ غیرعادی) با رنگ خطر.
  final bool danger;

  const SmartCard({
    super.key,
    required this.icon,
    required this.title,
    required this.reason,
    this.actionLabel,
    this.onAction,
    this.accent,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final tint = danger ? scheme.error : (accent ?? scheme.primary);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SSpace.md, vertical: SSpace.xs),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: SRadius.all(SRadius.tile),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              tint.withValues(alpha: dark ? .18 : .09),
              SColor.gold.withValues(alpha: dark ? .10 : .16),
            ],
          ),
          border: Border.all(color: tint.withValues(alpha: dark ? .34 : .20)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SSpace.md, SSpace.md, SSpace.md, SSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: SRadius.all(SRadius.chip),
                ),
                child: Icon(icon, size: 15, color: Colors.white),
              ),
              const SizedBox(width: SSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: SType.small,
                        fontWeight: FontWeight.w800,
                        height: 1.5,
                        color: danger ? scheme.error : scheme.primary,
                      ),
                    ),
                    const SizedBox(height: SSpace.xxs),
                    Text(
                      reason,
                      style: TextStyle(
                        fontSize: SType.micro + .5,
                        height: 1.65,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: SSpace.sm),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          onPressed: onAction,
                          style: TextButton.styleFrom(
                            foregroundColor: tint,
                            padding: const EdgeInsets.symmetric(horizontal: SSpace.sm, vertical: 0),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(fontSize: SType.micro + .5, fontWeight: FontWeight.w700),
                          ),
                          child: Text(actionLabel!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ردیف آمار برای صفحهٔ گزارش‌ها: برچسب کوچک بالا، عدد بزرگ پایین، نوار نسبت اختیاری.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final double? fraction;
  final bool positive;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.fraction,
    this.positive = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final tone = positive ? (dark ? SColor.successNight : SColor.success) : scheme.error;

    return Container(
      padding: const EdgeInsets.fromLTRB(SSpace.md, SSpace.md, SSpace.md, SSpace.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: SRadius.all(SRadius.tile),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: SType.micro, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
          const SizedBox(height: SSpace.xxs),
          // عدد با BidiText ایمن می‌شود تا در چیدمان راست‌به‌چپ جابه‌جا نشود.
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              height: 1.3,
              letterSpacing: -.01,
              color: tone,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (fraction != null) ...[
            const SizedBox(height: SSpace.sm),
            ClipRRect(
              borderRadius: SRadius.all(99),
              child: LinearProgressIndicator(
                value: fraction!.clamp(0, 1).toDouble(),
                minHeight: 7,
                backgroundColor: scheme.surfaceContainerHigh,
                valueColor: AlwaysStoppedAnimation(tone),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
