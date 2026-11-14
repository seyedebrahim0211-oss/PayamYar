import 'package:flutter/material.dart';
import '../sms_bridge.dart';
import 'contact_picker.dart';

/// Adds a contact card as plain text to the SMS draft, never automatically sends.
/// An attached VCF requires MMS/file transfer and is outside SMS-only capabilities.
Future<String?> selectContactForSms(BuildContext context) async {
  try {
    final contacts = await SmsBridge.listContacts();
    if (!context.mounted) return null;
    if (contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('مخاطبی پیدا نشد؛ دسترسی مخاطبین را بررسی کنید.')));
      return null;
    }
    final selection = await showContactPicker(context, contacts: contacts,
      maxSelection: 1, selected: const {});
    if (selection == null || selection.isEmpty) return null;
    final phone = selection.first;
    final item = contacts.firstWhere((v) => SmsBridge.normalizeNumber(v['number'] ?? '') ==
      SmsBridge.normalizeNumber(phone), orElse: () => <String, String>{'name': '', 'number': phone});
    final name = (item['name'] ?? '').trim();
    // Plain text, readable in every SMS client, no attachment or background send.
    return 'مخاطب: ${name.isEmpty ? phone : name}\nشماره: $phone';
  } catch (_) {
    if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('خواندن مخاطبین ممکن نشد. اجازه مخاطبین را بررسی کنید.'))); }
    return null;
  }
}
