import 'message_logic.dart';

/// Privacy policy for SMS previews: bank account balances, amounts, card/account
/// numbers and identifiers are not rendered in the inbox or lockable chat until
/// that specific message is explicitly revealed by a tap. Search still runs
/// exclusively on the device over the original message.
class BankPrivacy {
  static final RegExp _digits = RegExp(
    r'[0-9۰-۹٠-٩]+(?:[ \t,،٬٫.\-/]+[0-9۰-۹٠-٩]+)*');

  static String conceal(String text) =>
      text.replaceAllMapped(_digits, (_) => '••••');

  static String preview(MessageCategory category, String text) =>
      category == MessageCategory.banking ? conceal(text) : text;
}
