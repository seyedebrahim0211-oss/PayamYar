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
  const ReleaseInfo({required this.version, required this.available, required this.url, required this.notes});
}

class UpdateService {
  static final _endpoint = Uri.parse(
    'https://honarmardomi.ir/wp-json/wp/v2/pages/14733?_fields=content');

  static Future<ReleaseInfo> check() async {
    final response = await http.get(_endpoint).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw const HttpException('Update endpoint unavailable');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final page = data['content'] as Map<String, dynamic>;
    final rendered = page['rendered'] as String;
    final match = RegExp(r'<pre[^>]*>(\{.*?\})</pre>', dotAll: true).firstMatch(rendered);
    if (match == null) throw const FormatException('Missing release information');
    final manifest = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final version = manifest['version'] as String? ?? '';
    final published = manifest['published'] == true;
    final url = Platform.isAndroid
        ? manifest['android_url'] as String? ?? ''
        : Platform.isWindows
            ? manifest['windows_url'] as String? ?? ''
            : '';
    final current = (await PackageInfo.fromPlatform()).version;
    final isNewer = _compareVersions(version, current) > 0;
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException('Invalid update URL');
      }
    }
    return ReleaseInfo(
      version: version,
      available: published && isNewer && url.isNotEmpty,
      url: published && isNewer ? url : '',
      notes: manifest['notes'] as String? ?? '',
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

  static Future<bool> openDownload(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
