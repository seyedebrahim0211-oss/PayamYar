/// Where this APK is distributed. Set at build time:
///   flutter build apk --dart-define=PAYAMYAR_STORE=bazaar   (Cafe Bazaar)
///   flutter build apk --dart-define=PAYAMYAR_STORE=myket    (Myket)
///   flutter build appbundle --dart-define=PAYAMYAR_STORE=googleplay (Google Play)
/// Without the define the build is the official honarmardomi.ir ("site") edition.
///
/// Store editions never download or install APKs themselves: Bazaar and Myket only allow
/// updates through the store, and their manifests drop REQUEST_INSTALL_PACKAGES.
class AppChannel {
  static const String id = String.fromEnvironment('PAYAMYAR_STORE', defaultValue: 'site');

  static bool get isSite => id == 'site';
  static bool get isBazaar => id == 'bazaar';
  static bool get isMyket => id == 'myket';
  static bool get isGooglePlay => id == 'googleplay';

  /// In-app download + install of new versions (site edition only).
  static bool get inAppUpdates => isSite;

  static String get storeName => isBazaar ? 'کافه‌بازار' : isMyket ? 'مایکت' : isGooglePlay ? 'Google Play' : 'honarmardomi.ir';

  /// Store page that receives updates and reviews.
  static String get storeUrl => isBazaar
      ? 'https://cafebazaar.ir/app/ir.honarmardomi.payamyar'
      : isMyket
          ? 'https://myket.ir/app/ir.honarmardomi.payamyar'
          : isGooglePlay
              ? 'https://play.google.com/store/apps'
              : 'https://honarmardomi.ir/payamyar/';
}
