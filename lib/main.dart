import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'app_store.dart';
import 'sms_bridge.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

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
        ..showSnackBar(SnackBar(content: Text(text)));
    settings.load();
    store.init();
  }

  @override
  void dispose() {
    store.dispose();
    settings.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: palettes[settings.palette], brightness: b);
    final dark = b == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Vazirmatn',
      scaffoldBackgroundColor: dark ? const Color(0xFF0F1A1E) : const Color(0xFFF7F8F7),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF0F1A1E) : const Color(0xFFF7F8F7),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontFamily: 'Vazirmatn', fontSize: 20, fontWeight: FontWeight.w800, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: dark ? const Color(0xFF17262B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF17262B) : Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 16, fontWeight: FontWeight.w700),
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
        scaffoldMessengerKey: messenger,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: settings.mode,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(settings.scale)),
            child: child!,
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
