import 'dart:async' show Timer;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_settings.dart';
import 'app_store.dart';
import 'design/tokens.dart';
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

class _PayamYarState extends State<PayamYar> with WidgetsBindingObserver {
  Timer? _nightClock;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && settings.autoNight && mounted) setState(() {});
  }
  final settings = AppSettings();
  final store = AppStore(android: SmsBridge.supported);
  final messenger = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nightClock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (settings.autoNight && mounted) setState(() {});
    });
    store.onNotice = (text) => messenger.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          content: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: settings.reduceEffects
                ? _noticeContent(text)
                : BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: _noticeContent(text),
                  ),
          ),
        ));
    store.settings = settings;
    settings.load();
    AppLock.instance.load();
    store.init();
  }

  Widget _noticeContent(String message) => Container(
    decoration: BoxDecoration(
      color: const Color(0xE91A4246),
      border: Border.all(color: const Color(0x668DC7BD)),
      borderRadius: BorderRadius.circular(18),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.info_outline_rounded, color: Color(0xFFDDC18A), size: 21),
      const SizedBox(width: 10),
      Flexible(child: Text(message,
        style: const TextStyle(fontFamily: 'Vazirmatn',
          color: Colors.white, fontSize: 13, height: 1.55))),
    ]),
  );

  @override
  void dispose() {
    _nightClock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    store.dispose();
    settings.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness b) {
    final String? selectedFont = settings.fontChoice == 0
        ? 'Vazirmatn'
        : settings.fontChoice == 2
            ? 'serif'
            : null;
    return STheme.build(
      brightness: b,
      seed: palettes[settings.palette],
      fontFamily: selectedFont,
      reduceEffects: settings.reduceEffects,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'سوسلنگ',
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
        themeMode: settings.effectiveMode(DateTime.now()),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(
              settings.scale * MediaQuery.textScalerOf(context).scale(16) / 16)),
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
