import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'security/vault.dart';

/// A private support conversation. The app never exposes an admin phone number.
class SupportEntry {
  final String role;
  final String body;
  final String time;
  const SupportEntry({required this.role, required this.body, required this.time});
  factory SupportEntry.fromJson(Map<String, dynamic> data) => SupportEntry(
    role: data['role'] == 'admin' ? 'admin' : 'user',
    body: data['body']?.toString() ?? '',
    time: data['time']?.toString() ?? '',
  );
}
class SupportTicket {
  final int id;
  final String subject;
  final String category;
  final String status;
  final List<SupportEntry> entries;
  const SupportTicket({required this.id, required this.subject,
    required this.category, required this.status, required this.entries});
  factory SupportTicket.fromJson(Map<String, dynamic> data) => SupportTicket(
    id: (data['id'] as num).toInt(),
    subject: data['subject']?.toString() ?? '',
    category: data['category']?.toString() ?? 'other',
    status: data['status']?.toString() ?? 'new',
    entries: [
      for (final row in (data['entries'] as List? ?? const []))
        if (row is Map) SupportEntry.fromJson(Map<String, dynamic>.from(row)),
    ],
  );
}

/// Ticket IDs are harmless locally; their random bearer secrets live in
/// Android Keystore, never SharedPreferences or web URLs.
class SupportService {
  static final Uri base = Uri.parse('https://honarmardomi.ir/wp-json/payamyar-help/v1/');
  static const _key = 'payamyar_support_tickets_v1';
  static const _maxTickets = 40;
  static String _secretName(int id) => 'support_ticket_$id';

  static Future<List<int>> savedIds() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_key) ?? const <String>[])
      .map(int.tryParse).whereType<int>().where((id) => id > 0)
      .take(_maxTickets).toList(growable: false);
  }
  static Future<int> create({required String category, required String subject,
      required String body, required String version}) async {
    final response = await http.post(base.resolve('tickets'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'category': category, 'subject': subject,
        'body': body, 'version': version}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 201) {
      throw StateError('ثبت گزارش انجام نشد (${response.statusCode})');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final id = (data['id'] as num?)?.toInt() ?? 0;
    final secret = data['secret']?.toString() ?? '';
    if (id <= 0 || !RegExp(r'^[a-f0-9]{64}$').hasMatch(secret)) {
      throw const FormatException('پاسخ پشتیبانی معتبر نیست');
    }
    await Vault.put(_secretName(id), secret);
    final p = await SharedPreferences.getInstance();
    final ids = [id, ...((await savedIds()).where((v) => v != id))];
    await p.setStringList(_key, ids.take(_maxTickets).map((v) => '$v').toList());
    return id;
  }
  static Future<SupportTicket> detail(int id) async {
    final secret = await Vault.get(_secretName(id));
    if (secret == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(secret)) {
      throw StateError('کلید امن پیگیری تیکت موجود نیست');
    }
    final response = await http.get(base.resolve('tickets/$id'),
      headers: {'X-PayamYar-Ticket': secret, 'Cache-Control': 'no-store'})
      .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw StateError('خواندن تیکت ممکن نیست (${response.statusCode})');
    return SupportTicket.fromJson(jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
  }
  static Future<SupportTicket> respond(int id, String message) async {
    final secret = await Vault.get(_secretName(id));
    if (secret == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(secret)) {
      throw StateError('کلید پیگیری در دسترس نیست');
    }
    final response = await http.post(base.resolve('tickets/$id/messages'),
      headers: {'X-PayamYar-Ticket': secret, 'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'body': message.trim()}))
      .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw StateError('پاسخ ارسال نشد (${response.statusCode})');
    return detail(id);
  }
}
