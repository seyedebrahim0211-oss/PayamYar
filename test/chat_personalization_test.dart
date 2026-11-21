import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/chat_personalization.dart';
import 'package:payamyar/app_settings.dart';

void main() {
  test('phone-number formats reuse one private chat appearance key', () {
    expect(ChatPersonalizations.canonical('+989121234567'),
      ChatPersonalizations.canonical('09121234567'));
    expect(ChatPersonalizations.canonical('00989121234567'),
      ChatPersonalizations.canonical('09121234567'));
    expect(ChatPersonalizations.canonical('Bank Mellat'), 'bank mellat');
  });

  test('visual preferences preserve independent per-contact values', () {
    const original = ChatRoomStyle(theme: ChatStyle.traditional, avatarPath: '/private/a.jpg');
    final next = original.withImage(wallpaper: true, path: '/private/w.webp');
    expect(next.avatarPath, '/private/a.jpg');
    expect(next.wallpaperPath, '/private/w.webp');
    expect(next.theme, ChatStyle.traditional);
    final restored = ChatRoomStyle.fromJson(next.toJson());
    expect(restored.avatarPath, next.avatarPath);
    expect(restored.wallpaperPath, next.wallpaperPath);
    expect(restored.theme, next.theme);
  });

  test('rejects unsupported image headers', () {
    expect(ChatPersonalizations.imageExtension(List<int>.filled(12, 0)), isNull);
    expect(ChatPersonalizations.imageExtension([0xFF,0xD8,0xFF,...List<int>.filled(9, 0)]), 'jpg');
    expect(ChatPersonalizations.imageExtension([0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0,0,0,0]), 'png');
  });
}
