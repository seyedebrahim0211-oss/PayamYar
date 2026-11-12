import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'sms_bridge.dart';

class ReleaseInfo {
  final String version;
  final bool available;
  final String url;
  final String notes;
  /// SHA-256 of the file served by honarmardomi.ir (APK or ZIP), never an APK extracted from the ZIP.
  final String sha256;
  /// Size in bytes of the published file, 0 when unknown.
  final int sizeBytes;
  const ReleaseInfo({
    required this.version,
    required this.available,
    required this.url,
    required this.notes,
    this.sha256 = '',
    this.sizeBytes = 0,
  });

  /// Human readable Persian size, e.g. «۲۴٫۳ مگابایت».
  String get sizeLabel => formatBytes(sizeBytes);
}

/// Formats a byte count for Persian UI; empty for unknown sizes.
String formatBytes(int bytes) {
  if (bytes <= 0) return '';
  const digits = '۰۱۲۳۴۵۶۷۸۹';
  String fa(String s) => s.split('').map((c) {
    final d = int.tryParse(c);
    return d == null ? (c == '.' ? '٫' : c) : digits[d];
  }).join();
  if (bytes < 1024 * 1024) return '${fa((bytes / 1024).toStringAsFixed(0))} کیلوبایت';
  return '${fa((bytes / (1024 * 1024)).toStringAsFixed(1))} مگابایت';
}

class UpdateService {
  // Server-side administrator release manager: no GitHub, credentials or tokens in the app.
  static final _endpoint = Uri.parse('https://honarmardomi.ir/wp-json/payamyar/v1/release');
  /// Release identity is verified against the APK's real signing certificate,
  /// not a value in private storage. Preview builds cannot opt into official updates.
  static Future<Map<String, dynamic>> _readManifest() async {
    final headers = <String, String>{'Cache-Control': 'no-cache'};
    if (Platform.isAndroid) {
      try {
        final signer = await SmsBridge.signingFingerprint();
        if (validDigest(signer)) headers['X-PayamYar-Signer'] = signer;
      } catch (_) {
        // Older builds without the bridge receive no update, rather than
        // bypassing signer checks via an unauthenticated legacy manifest.
      }
    }
    final response = await http.get(_endpoint, headers: headers)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const HttpException('Official PayamYar release endpoint unavailable');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<ReleaseInfo> check() async {
    final manifest = await _readManifest();
    final version = manifest['version'] as String? ?? '';
    final published = manifest['published'] == true;
    final url = Platform.isAndroid
        ? manifest['android_url'] as String? ?? ''
        : Platform.isWindows
            ? manifest['windows_url'] as String? ?? ''
            : '';
    final digest = manifest['sha256'] as String? ?? '';
    final size = (manifest['size_bytes'] as num?)?.toInt() ?? 0;
    final current = (await PackageInfo.fromPlatform()).version;
    final minimumSupported = manifest['minimum_supported_version'] as String? ?? '1.0.0';
    final compatible = _compareVersions(current, minimumSupported) >= 0;
    final isNewer = _compareVersions(version, current) > 0;
    if (url.isNotEmpty && !trusted(url)) {
      throw const FormatException('Invalid update URL');
    }
    if (published && url.isNotEmpty && !validDigest(digest)) {
      throw const FormatException('Missing or invalid official release checksum');
    }
    return ReleaseInfo(
      version: version,
      available: published && compatible && isNewer && url.isNotEmpty,
      url: published && compatible && isNewer ? url : '',
      notes: manifest['notes'] as String? ?? '',
      sha256: published && compatible && isNewer ? digest.toLowerCase() : '',
      sizeBytes: size > 0 && size <= 140 * 1024 * 1024 ? size : 0,
    );
  }

  /// A published release must include a 64-character hexadecimal SHA-256.
  static bool validDigest(String value) {
    if (value.length != 64) return false;
    for (final code in value.codeUnits) {
      final hex = (code >= 48 && code <= 57) ||
          (code >= 65 && code <= 70) || (code >= 97 && code <= 102);
      if (!hex) return false;
    }
    return true;
  }

  static int compareVersions(String a, String b) => _compareVersions(a, b);

  static int _compareVersions(String a, String b) {
    List<int> parse(String value) => value.split('+').first.split('.')
        .map((part) => int.tryParse(part) ?? 0).toList();
    final x = parse(a), y = parse(b);
    for (var i = 0; i < 3; i++) {
      final left = i < x.length ? x[i] : 0;
      final right = i < y.length ? y[i] : 0;
      if (left != right) return left.compareTo(right);
    }
    return 0;
  }

  /// Official HTTPS APK/ZIP hosted on honarmardomi.ir only.
  static bool trusted(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' ||
        (uri.host != 'honarmardomi.ir' && uri.host != 'www.honarmardomi.ir') ||
        uri.userInfo.isNotEmpty || uri.hasFragment || (uri.hasPort && uri.port != 443)) {
      return false;
    }
    return uri.path.toLowerCase().endsWith('.apk') || uri.path.toLowerCase().endsWith('.zip');
  }

  static Future<bool> openDownload(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
