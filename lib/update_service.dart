import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class ReleaseInfo {
  final String version;
  final bool available;
  final String url;
  final String notes;
  /// SHA-256 of the file served by honarmardomi.ir (APK or ZIP), never an APK extracted from the ZIP.
  final String sha256;
  const ReleaseInfo({
    required this.version,
    required this.available,
    required this.url,
    required this.notes,
    this.sha256 = '',
  });
}

class UpdateService {
  // Server-side administrator release manager: no GitHub, credentials or tokens in the app.
  static final _endpoint = Uri.parse('https://honarmardomi.ir/wp-json/payamyar/v1/release');
  // Existing installations still read this legacy page; the WordPress manager keeps it in sync.
  static final _legacyEndpoint = Uri.parse(
      'https://honarmardomi.ir/wp-json/wp/v2/pages/14733?_fields=content');

  static Future<Map<String, dynamic>> _readManifest() async {
    final response = await http.get(_endpoint, headers: {'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    }
    // The fallback is on the SAME official site; it never redirects to third-party hosts.
    final old = await http.get(_legacyEndpoint, headers: {'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 12));
    if (old.statusCode != 200) throw const HttpException('PayamYar release endpoint unavailable');
    final data = jsonDecode(utf8.decode(old.bodyBytes)) as Map<String, dynamic>;
    final page = data['content'] as Map<String, dynamic>;
    final rendered = page['rendered'] as String;
    final match = RegExp(r'<pre[^>]*>(\{.*?\})</pre>', dotAll: true).firstMatch(rendered);
    if (match == null) throw const FormatException('Missing release information');
    return jsonDecode(match.group(1)!) as Map<String, dynamic>;
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
    final current = (await PackageInfo.fromPlatform()).version;
    final isNewer = _compareVersions(version, current) > 0;
    if (url.isNotEmpty && !trusted(url)) {
      throw const FormatException('Invalid update URL');
    }
    if (published && url.isNotEmpty &&
        (digest.isNotEmpty && !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(digest))) {
      throw const FormatException('Invalid release checksum');
    }
    return ReleaseInfo(
      version: version,
      available: published && isNewer && url.isNotEmpty,
      url: published && isNewer ? url : '',
      notes: manifest['notes'] as String? ?? '',
      sha256: published && isNewer ? digest.toLowerCase() : '',
    );
  }

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
