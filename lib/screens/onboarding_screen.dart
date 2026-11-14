import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_store.dart';
import '../brand_mark.dart';
import '../sms_bridge.dart';

/// First-run pages: (1) grant SMS, contacts and notification access, (2) make PayamYar the default SMS app.
class OnboardingScreen extends StatefulWidget {
  final AppStore store;
  const OnboardingScreen({super.key, required this.store});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool busy = false;
  bool denied = false;

  AppStore get store => widget.store;
  // Google Play requires the default SMS role *before* requesting restricted SMS access.
  bool get permissionStep => store.permissions.isDefault && !store.permissions.canRead;

  Future<void> _grant() async {
    setState(() => busy = true);
    try {
      final state = await store.requestPermissions();
      if (mounted) setState(() => denied = !state.canRead);
      if (state.canRead && state.isDefault) await store.finishOnboarding();
    } catch (_) {
      if (mounted) setState(() => denied = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _makeDefault() async {
    setState(() => busy = true);
    try {
      await store.requestDefault();
    } catch (_) {
      // The user can still continue; the inbox shows a reminder card.
    }
    await store.checkPermissions();
    if (store.permissions.isDefault && store.permissions.canRead) {
      await store.finishOnboarding();
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String title, body, action;
    if (permissionStep) {
      title = denied ? 'دسترسی لازم است' : 'به پیامیار خوش آمدید';
      body = denied
          ? 'بدون دسترسی پیامک، پیامیار نمی‌تواند پیام‌های گوشی را نمایش دهد. دوباره «اجازه دادن» را بزنید یا از تنظیمات گوشی، دسترسی پیامک را برای پیامیار روشن کنید.'
          : 'خواندن و ارسال پیامک برای پیام‌رسانی، دسترسی مخاطبین برای نام‌ها و دسترسی اعلان‌ها برای هشدار پیام جدید است. دسترسی مخاطبین و اعلان‌ها را می‌توانید در تنظیمات گوشی تغییر دهید. محتوای پیام‌ها برای قابلیت‌های معمول روی دستگاه تحلیل می‌شود.';
      action = denied ? 'اجازه دادن دوباره' : 'اجازه دسترسی';
    } else {
      title = 'پیامیار را فعال کنید';
      body = 'ابتدا به انتخاب خودتان پیامیار را پیام‌رسان پیش‌فرض گوشی کنید. تنها پس از این مرحله، دسترسی‌های حساس پیامک درخواست می‌شوند. با لغو این انتخاب، پیامیار باید استفاده از مجوزهای پیامک را متوقف کند.';
      action = 'انتخاب پیام‌رسان پیش‌فرض';
    }
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _Dot(active: permissionStep, color: scheme.primary),
              const SizedBox(width: 6),
              _Dot(active: !permissionStep, color: scheme.primary),
            ]),
            const SizedBox(height: 18),
            const PayamYarLogotype(height: 48, tagline: true),
            const Spacer(),
            const SizedBox(width: 260, height: 210, child: CustomPaint(painter: OnboardingArt())),
            const SizedBox(height: 28),
            Text(title, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Text(body, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant, height: 1.8)),
            const Spacer(),
            FilledButton(
              onPressed: busy ? null : (permissionStep ? _grant : _makeDefault),
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : Text(action),
            ),
            const SizedBox(height: 6),
            if (permissionStep && denied)
              TextButton(onPressed: SmsBridge.openAppSettings, child: const Text('باز کردن تنظیمات گوشی'))
            else if (!permissionStep)
              TextButton(onPressed: busy ? null : () => SmsBridge.openAppSettings(), child: const Text('تنظیمات برنامه'))
            else
              const SizedBox(height: 48),
          ]),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  final Color color;
  const _Dot({required this.active, required this.color});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    width: active ? 22 : 8,
    height: 8,
    decoration: BoxDecoration(
      color: active ? color : color.withValues(alpha: .25),
      borderRadius: BorderRadius.circular(8)),
  );
}

/// PayamYar's own onboarding illustration: a phone with the message emblem, two cards and confetti.
class OnboardingArt extends CustomPainter {
  const OnboardingArt();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2 + 6;
    final outline = Paint()
      ..color = const Color(0xFF1B2B30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeJoin = StrokeJoin.round;

    void card(double dx, double angle, Color color) {
      canvas.save();
      canvas.translate(cx + dx, cy - 6);
      canvas.rotate(angle);
      final r = RRect.fromRectAndRadius(const Rect.fromLTWH(-38, -58, 76, 112), const Radius.circular(12));
      canvas.drawRRect(r, Paint()..color = color);
      canvas.drawRRect(r, outline);
      canvas.restore();
    }

    card(-46, -0.32, const Color(0xFFF4B740));
    card(46, 0.28, const Color(0xFFE76F51));

    final phone = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 10), width: 96, height: 150), const Radius.circular(16));
    canvas.drawRRect(phone, Paint()..color = Colors.white);
    canvas.drawRRect(phone, outline);
    final screen = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy + 4), width: 76, height: 104), const Radius.circular(8));
    canvas.drawRRect(screen, Paint()..color = const Color(0xFF14B3B0));
    canvas.drawLine(Offset(cx - 12, cy + 74), Offset(cx + 12, cy + 74), outline..strokeWidth = 3);

    canvas.drawCircle(Offset(cx, cy + 4), 27, Paint()..color = Colors.white);
    final bubble = Paint()
      ..color = const Color(0xFF087F81)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final b = Path()
      ..moveTo(cx - 14, cy - 6)
      ..quadraticBezierTo(cx - 14, cy - 11, cx - 9, cy - 11)
      ..lineTo(cx + 9, cy - 11)
      ..quadraticBezierTo(cx + 14, cy - 11, cx + 14, cy - 6)
      ..lineTo(cx + 14, cy + 6)
      ..quadraticBezierTo(cx + 14, cy + 11, cx + 9, cy + 11)
      ..lineTo(cx - 3, cy + 11)
      ..lineTo(cx - 9, cy + 18)
      ..lineTo(cx - 9, cy + 11)
      ..quadraticBezierTo(cx - 14, cy + 11, cx - 14, cy + 6)
      ..close();
    canvas.drawPath(b, bubble);
    final gold = Paint()
      ..color = const Color(0xFFE0A526)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - 6, cy + 5), Offset(cx + 9, cy - 7), gold);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    void triangle(Offset c, double s, Color color) {
      final p = Path()
        ..moveTo(c.dx, c.dy - s)
        ..lineTo(c.dx + s, c.dy + s * .8)
        ..lineTo(c.dx - s, c.dy + s * .8)
        ..close();
      canvas.drawPath(p, stroke..color = color);
    }
    void cross(Offset c, double s, Color color, {bool plus = false}) {
      stroke.color = color;
      if (plus) {
        canvas.drawLine(c.translate(-s, 0), c.translate(s, 0), stroke);
        canvas.drawLine(c.translate(0, -s), c.translate(0, s), stroke);
      } else {
        canvas.drawLine(c.translate(-s, -s), c.translate(s, s), stroke);
        canvas.drawLine(c.translate(s, -s), c.translate(-s, s), stroke);
      }
    }

    cross(Offset(w * .18, h * .14), 6, const Color(0xFF1B2B30));
    cross(Offset(w * .45, h * .07), 7, const Color(0xFF1B2B30), plus: true);
    canvas.drawCircle(Offset(w * .62, h * .1), 5, stroke..color = const Color(0xFF1B2B30));
    triangle(Offset(w * .84, h * .17), 8, const Color(0xFFF4B740));
    triangle(Offset(w * .06, h * .5), 7, const Color(0xFF14B3B0));
    triangle(Offset(w * .95, h * .66), 6, const Color(0xFF1B2B30));
    canvas.drawCircle(Offset(w * .4, h * .2), 6, stroke..color = const Color(0xFF14B3B0));
    canvas.drawArc(Rect.fromCircle(center: Offset(w * .93, h * .33), radius: 12), -math.pi * .9, math.pi * .5, false,
      stroke..color = const Color(0xFF14B3B0));
    canvas.drawArc(Rect.fromCircle(center: Offset(w * .1, h * .78), radius: 12), math.pi * .1, math.pi * .5, false,
      stroke..color = const Color(0xFFF4B740));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
