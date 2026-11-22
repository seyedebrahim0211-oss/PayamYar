import 'package:flutter/material.dart';

/// Informational limits only: carrier quotas may vary by contract, network,
/// policy, SMS segments and other messages sent outside PayamYar.
/// Do not imply these reported figures have been verified with MCI.
class CarrierSmsLimits extends StatelessWidget {
  final bool compact;
  const CarrierSmsLimits({super.key, this.compact = false});

  static const prepaid = 500;
  static const postpaid = 1000;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.info_outline_rounded, size: 19, color: colors.primary),
            const SizedBox(width: 7),
            Expanded(child: Text('راهنمای سقف پیامک همراه اول (۲۴ ساعت)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 7),
          Wrap(spacing: 7, runSpacing: 6, children: [
            Chip(
              visualDensity: VisualDensity.compact,
              label: const Text('اعتباری: ۵۰۰ پیامک'),
              avatar: const Icon(Icons.sim_card_outlined, size: 16),
            ),
            Chip(
              visualDensity: VisualDensity.compact,
              label: const Text('دائمی: ۱٬۰۰۰ پیامک'),
              avatar: const Icon(Icons.sim_card_rounded, size: 16),
            ),
          ]),
          Text(
            'این اعداد اعلام‌شده‌اند، نه سهمیه تأییدشده توسط همراه اول. '
            'ممکن است محدودیت‌های ساعتی یا روزانه کمتر باشد؛ '
            'ارسال پیامک چندبخشی ممکن است چند واحد حساب شود. '
            'پیام‌یار به مانده سهمیه اپراتور دسترسی ندارد.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontSize: compact ? 11 : 12,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
