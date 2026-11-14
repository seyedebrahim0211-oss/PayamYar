import 'dart:convert';
import 'package:http/http.dart' as http;
import 'security/vault.dart';

/// Only handles site-managed authorization; never uploads SMS or contacts.
class SiteAdminAuth {
  static const _url = 'https://honarmardomi.ir/wp-json/payamyar-auth/v1';
  static const _tokenKey = 'honar_site_admin_token';
  static const _userKey = 'honar_site_admin_user';

  static Future<bool> paired() async {
    final t = await Vault.get(_tokenKey);
    final u = await Vault.get(_userKey);
    return t != null && t.length == 64 && u != null && int.tryParse(u) != null;
  }

  /// Defaults to deny if the website is offline or access has been revoked.
  static Future<bool> authorized() async {
    final token = await Vault.get(_tokenKey);
    final uid = await Vault.get(_userKey);
    if (token == null || uid == null || token.length != 64) return false;
    try {
      final response = await http.get(Uri.parse('$_url/status'), headers: {
        'Accept': 'application/json',
        'X-Payamyar-Token': token,
        'X-Payamyar-User': uid,
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      final body = jsonDecode(response.body);
      return body is Map && body['authorized'] == true &&
          body['user_id']?.toString() == uid;
    } catch (_) {
      return false;
    }
  }

  /// Pairs after the WordPress site administrator generates a one-time code.
  static Future<String?> link(String pairingCode) async {
    final code = pairingCode.trim().toLowerCase();
    if (!RegExp(r'^[0-9]{1,10}-[a-f0-9]{32}$').hasMatch(code)) {
      return 'کد اتصال نامعتبر است؛ کد کامل صادرشده از سایت را وارد کنید.';
    }
    try {
      final response = await http.post(
        Uri.parse('$_url/pair'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        return response.statusCode == 429
          ? 'تلاش‌های زیاد ثبت شده؛ پس از ۱۵ دقیقه دوباره امتحان کنید.'
          : 'کد نامعتبر یا منقضی شده است. از مدیر سایت کد جدید بگیرید.';
      }
      final data = jsonDecode(response.body);
      if (data is! Map || data['authorized'] != true ||
          data['token'] is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['token']) ||
          data['user_id'] is! int) {
        return 'پاسخ تأیید سایت معتبر نیست.';
      }
      await Vault.put(_tokenKey, data['token']);
      await Vault.put(_userKey, data['user_id'].toString());
      if (!await authorized()) return 'مجوز جدید از سمت سایت تأیید نشد؛ اتصال را بررسی کنید.';
      return null;
    } catch (_) {
      return 'اتصال ایمن به هنر مردمی برقرار نشد. اینترنت و سایت را بررسی کنید.';
    }
  }

  static Future<void> unlink() async {
    await Vault.remove(_tokenKey);
    await Vault.remove(_userKey);
  }
}
