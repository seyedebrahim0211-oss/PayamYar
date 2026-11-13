import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_settings.dart';
import 'app_store.dart';
import 'sms_bridge.dart';
import 'screens/glass_banner.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'security/app_lock.dart';

export 'app_settings.dart';

void main() => runApp(const PayamYar());

class PayamYar extends StatefulWidget {
  const PayamYar({super.key});
  @override
  State<PayamYar> createState() => _PayamYarState();
}

class _PayamYarState extends State<PayamYar> {
  final settings = AppSettings();
  final store = AppStore(android: SmsBridge.supported);
  final messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    store.onNotice = (text) => messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          content: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xE91A4246),
                  border: Border.all(color: const Color(0x668DC7BD)),
                  borderRadius: BorderRadius.circular(18),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFDDC18A), size: 21),
                  const SizedBox(width: 10),
                  Flexible(child: Text(text, style: const TextStyle(fontFamily: 'Vazirmatn',
                    color: Colors.white, fontSize: 13, height: 1.55))),
                ]),
              ),
            ),
          ),
        ));
    store.settings = settings;
    settings.load();
    AppLock.instance.load();
    store.init();
  }

  @override
  void dispose() {
    store.dispose();
    settings.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness b) {
    final dark = b == Brightness.dark;
    final String? selectedFont = settings.fontChoice == 0 ? 'Vazirmatn' : settings.fontChoice == 2 ? 'serif' : null;
    // Teal identity with a warm gold accent on paper-like backgrounds.
    final scheme = ColorScheme.fromSeed(seedColor: palettes[settings.palette], brightness: b).copyWith(
      tertiary: dark ? const Color(0xFFE7C57C) : const Color(0xFF8A6417),
      tertiaryContainer: dark ? const Color(0xFF4A3A14) : const Color(0xFFFCEBC4),
      onTertiaryContainer: dark ? const Color(0xFFFCEBC4) : const Color(0xFF3F2E05));
    final paper = dark ? const Color(0xFF0E1B1F) : const Color(0xFFFAF8F3);
    final surface = dark ? const Color(0xFF172A30) : Colors.white;
    final base = dark ? Typography.material2021().white : Typography.material2021().black;
    TextStyle? fa(TextStyle? s, {double? size, FontWeight? weight, double height = 1.6}) => s?.copyWith(
      fontFamily: selectedFont, fontSize: size, fontWeight: weight, height: height, letterSpacing: 0);
    final text = base.copyWith(
      headlineSmall: fa(base.headlineSmall, size: 24, weight: FontWeight.w800, height: 1.5),
      titleLarge: fa(base.titleLarge, size: 20, weight: FontWeight.w800, height: 1.5),
      titleMedium: fa(base.titleMedium, size: 16, weight: FontWeight.w700),
      titleSmall: fa(base.titleSmall, size: 14, weight: FontWeight.w700),
      bodyLarge: fa(base.bodyLarge, size: 16, height: 1.8),
      bodyMedium: fa(base.bodyMedium, size: 14.5, height: 1.7),
      bodySmall: fa(base.bodySmall, size: 12.5),
      labelLarge: fa(base.labelLarge, size: 14, weight: FontWeight.w700),
      labelMedium: fa(base.labelMedium, size: 12.5, weight: FontWeight.w600),
      labelSmall: fa(base.labelSmall, size: 11.5, weight: FontWeight.w600),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: selectedFont,
      textTheme: text,
      scaffoldBackgroundColor: paper,
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(fontFamily: selectedFont, fontSize: 20, fontWeight: FontWeight.w800, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        height: 68,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        extendedTextStyle: TextStyle(fontFamily: selectedFont, fontWeight: FontWeight.w700, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
        labelStyle: TextStyle(fontFamily: selectedFont, fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: paper, surfaceTintColor: Colors.transparent),
      dialogTheme: DialogThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
      listTileTheme: const ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: TextStyle(fontFamily: selectedFont, fontSize: 16, fontWeight: FontWeight.w700),
      )),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'پیامیار',
        debugShowCheckedModeBanner: false,
        locale: const Locale('fa', 'IR'),
        supportedLocales: const [Locale('fa', 'IR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        scaffoldMessengerKey: messenger,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: settings.mode,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(settings.scale)),
            child: LockGate(
              lock: AppLock.instance,
              child: BannerHost(store: store, settings: settings, child: child!),
            ),
          ),
        ),
        home: RootGate(store: store, settings: settings),
      ),
    );
  }
}

/// Shows the welcome/permission pages until the phone's messages can be read, then the inbox.
class RootGate extends StatelessWidget {
  final AppStore store;
  final AppSettings settings;
  const RootGate({super.key, required this.store, required this.settings});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (!store.initialized) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (store.needsOnboarding) return OnboardingScreen(store: store);
        return HomeShell(store: store, settings: settings);
      },
    );
  }
}
