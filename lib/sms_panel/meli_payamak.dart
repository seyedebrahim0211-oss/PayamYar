import 'dart:convert';
import 'package:http/http.dart' as http;

/// One message from the Meli Payamak panel (received or sent).
class PanelMessage {
  final int id;
  final String sender;
  final String receiver;
  final String body;
  final DateTime? date;
  final bool read;
  const PanelMessage({required this.id, required this.sender, required this.receiver, required this.body,
      this.date, this.read = true});

  static PanelMessage? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String s(List<String> keys) {
      for (final k in keys) {
        final v = raw[k];
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
      return '';
    }

    final body = s(['Body', 'body', 'Text', 'text', 'MsgBody']);
    final id = int.tryParse(s(['MsgID', 'MsgId', 'msgID', 'Id', 'ID', 'id'])) ?? 0;
    return PanelMessage(
      id: id,
      sender: s(['Sender', 'sender', 'From', 'from']),
      receiver: s(['Receiver', 'receiver', 'To', 'to']),
      body: body,
      date: parseDate(s(['SendDate', 'sendDate', 'Date', 'date', 'ReceiveDate'])),
      read: raw['IsRead'] != false,
    );
  }

  /// Accepts ISO dates and the ASP.NET "/Date(1699999999999)/" form.
  static DateTime? parseDate(String v) {
    if (v.isEmpty) return null;
    final ms = RegExp(r'/Date\((\d+)').firstMatch(v);
    if (ms != null) return DateTime.fromMillisecondsSinceEpoch(int.parse(ms.group(1)!));
    return DateTime.tryParse(v)?.toLocal();
  }
}

class PanelException implements Exception {
  final String message;
  const PanelException(this.message);
  @override
  String toString() => message;
}

/// Client for the Meli Payamak REST web service (rest.payamak-panel.com).
///
/// Credentials are the panel username and the API key (or password) from
/// «تنظیمات › وب‌سرویس» in the panel. They are kept in the Android Keystore vault
/// and sent only over HTTPS to the official web service host.
class MeliPayamak {
  static const host = 'rest.payamak-panel.com';
  static const defaultLine = '90008325';
  static const panelUrl = 'https://panel.melipayamak.com/';
  static const chargeUrl = 'https://www.melipayamak.com/price/';

  final String username;
  final String password;
  final http.Client _client;
  MeliPayamak(this.username, this.password, {http.Client? client}) : _client = client ?? http.Client();

  void close() => _client.close();

  Future<Map<String, dynamic>> _post(String method, Map<String, String> fields) async {
    final uri = Uri.https(host, '/api/SendSMS/$method');
    final http.Response res;
    try {
      res = await _client
          .post(uri,
              headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8', 'Accept': 'application/json'},
              body: {'username': username, 'password': password, ...fields})
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const PanelException('اتصال به ملی پیامک برقرار نشد؛ اینترنت را بررسی کنید.');
    }
    if (res.statusCode != 200) throw PanelException('پاسخ نامعتبر از ملی پیامک (کد ${res.statusCode}).');
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw const PanelException('پاسخ ملی پیامک قابل خواندن نیست.');
    }
    if (json is! Map) throw const PanelException('پاسخ ملی پیامک قابل خواندن نیست.');
    return json.cast<String, dynamic>();
  }

  /// Persian text for the error codes returned in "Value" by the web service.
  static String errorText(String code) {
    const map = {
      '0': 'نام کاربری یا رمز/کلید وب‌سرویس نادرست است.',
      '2': 'اعتبار پنل کافی نیست؛ پنل را شارژ کنید.',
      '3': 'محدودیت ارسال روزانه پر شده است.',
      '4': 'محدودیت حجم ارسال پر شده است.',
      '5': 'شماره فرستنده (خط) معتبر نیست.',
      '6': 'سامانه در حال به‌روزرسانی است؛ کمی بعد تلاش کنید.',
      '7': 'متن شامل کلمه فیلترشده است.',
      '9': 'ارسال از خط عمومی با وب‌سرویس مجاز نیست.',
      '10': 'کاربر غیرفعال است.',
      '11': 'پیامک ارسال نشد.',
      '12': 'مدارک کاربری پنل کامل نیست.',
      '14': 'متن شامل لینک است و مجاز نیست.',
      '15': 'برای ارسال به چند گیرنده، عبارت «لغو11» باید در انتهای متن باشد.',
      '16': 'گیرنده‌ای پیدا نشد.',
      '17': 'متن پیامک خالی است.',
      '18': 'شماره گیرنده معتبر نیست.',
      '35': 'شماره گیرنده در فهرست سیاه مخابرات است.',
      '108': 'به دلیل تلاش‌های ناموفق، IP شما مسدود شده است.',
      '109': 'باید IP مجاز برای وب‌سرویس در پنل تعریف شود.',
      '110': 'به‌جای رمز عبور، «کلید وب‌سرویس (API Key)» پنل را وارد کنید.',
    };
    final clean = code.replaceAll('-', '').trim();
    return map[clean] ?? 'خطای ملی پیامک (کد $code).';
  }

  static bool _ok(Map<String, dynamic> r) => r['RetStatus'] == 1 || r['RetStatus']?.toString() == '1';

  /// Remaining panel credit (number of SMS).
  Future<double> credit() async {
    final r = await _post('GetCredit', const {});
    final value = r['Value']?.toString() ?? '';
    final n = double.tryParse(value);
    if (!_ok(r) || n == null) throw PanelException(value.isEmpty || value == 'NULL' ? errorText('0') : errorText(value));
    return n;
  }

  /// Return the provider's confirmed receipt ID when present. Some accounts
  /// return RetStatus=1 with a missing/short Value; that is an accepted request
  /// without a usable tracking ID, NOT a failed send. Never retry automatically.
  static String receiptFromResponse(Map<String, dynamic> reply) {
    if (!_ok(reply)) {
      final raw = reply['Value']?.toString() ?? '';
      throw PanelException(errorText(raw.isEmpty ? '0' : raw));
    }
    final raw = reply['Value']?.toString().trim() ?? '';
    if (raw.isEmpty || raw.toUpperCase() == 'NULL') return '';
    final numbers = RegExp(r'^\\d+$');
    if (numbers.hasMatch(raw) && int.tryParse(raw) != null && int.parse(raw) > 0) {
      return raw;
    }
    // A successful status matters more than an absent/non-numeric receipt.
    return '';
  }

  /// Sends at most 100 opt-in recipients using one request.
  /// If transport fails after POST, the result is unknown: the caller must not
  /// automatically resend because the gateway may have processed the request.
  Future<String> send({required List<String> to, required String text, String from = defaultLine, bool flash = false}) async {
    final numbers = [for (final n in to) normalize(n)].where((n) => n.isNotEmpty).toSet().toList();
    if (numbers.isEmpty) throw PanelException(errorText('18'));
    if (numbers.length > 100) throw const PanelException('در هر ارسال حداکثر ۱۰۰ گیرنده مجاز است.');
    if (text.trim().isEmpty) throw PanelException(errorText('17'));
    try {
      final response = await _post('SendSMS', {
        'to': numbers.join(','),
        'from': from,
        'text': text,
        'isFlash': flash ? 'true' : 'false',
      });
      return receiptFromResponse(response);
    } on PanelException catch (e) {
      if (e.message.startsWith('اتصال به ملی پیامک برقرار نشد')) {
        throw const PanelException(
          'وضعیت ارسال نامشخص است. ممکن است پیام به پنل رسیده باشد. پیش از ارسال دوباره، صندوق ارسالی و گزارش تحویل را بررسی کنید.');
      }
      rethrow;
    }
  }

  /// [location]: 1 = received, 2 = sent. [from] filters by the sender number (received box).
  Future<List<PanelMessage>> messages({int location = 1, String from = '', int index = 0, int count = 50}) async {
    final r = await _post('GetMessages', {
      'location': '$location',
      'from': from,
      'index': '$index',
      'count': '$count',
    });
    if (!_ok(r)) throw PanelException(errorText(r['Value']?.toString() ?? '0'));
    Object? data = r['Data'] ?? r['ReturnValue'] ?? r['Value'];
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        data = const [];
      }
    }
    if (data is Map) data = data['MessagesBL'] ?? data['Messages'] ?? data.values.firstWhere((v) => v is List, orElse: () => const []);
    if (data is! List) return const [];
    return data.map(PanelMessage.fromJson).whereType<PanelMessage>().toList()
      ..sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
  }

  /// Delivery status of a send. Returns the raw status code text.
  Future<String> delivery(String recId) async {
    final r = await _post('GetDeliveries2', {'recID': recId});
    return r['Value']?.toString() ?? '';
  }

  static String deliveryText(String code) => switch (code) {
        '0' => 'در صف ارسال',
        '1' => 'رسیده به گوشی',
        '2' => 'نرسیده به گوشی',
        '3' => 'خطای مخابراتی',
        '5' => 'خطای نامشخص',
        '8' => 'رسیده به مخابرات',
        '16' => 'نرسیده به مخابرات',
        '35' => 'در فهرست سیاه',
        '100' => 'نامشخص',
        '200' => 'ارسال‌شده',
        '300' => 'فیلترشده',
        '400' => 'در لیست ارسال',
        '500' => 'عدم پذیرش',
        '-1' || '1-' => 'شناسه ارسال پیدا نشد',
        _ => 'وضعیت $code',
      };

  /// 09xxxxxxxxx form; empty for invalid input.
  static String normalize(String raw) {
    const fa = '۰۱۲۳۴۵۶۷۸۹', ar = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final ch in raw.split('')) {
      final p = fa.indexOf(ch), a = ar.indexOf(ch);
      if (p >= 0) {
        b.write(p);
      } else if (a >= 0) {
        b.write(a);
      } else if (RegExp(r'\d').hasMatch(ch)) {
        b.write(ch);
      }
    }
    var d = b.toString();
    if (d.startsWith('0098')) d = '0${d.substring(4)}';
    if (d.startsWith('98') && d.length == 12) d = '0${d.substring(2)}';
    if (d.length == 10 && d.startsWith('9')) d = '0$d';
    return RegExp(r'^09\d{9}$').hasMatch(d) ? d : '';
  }
}
