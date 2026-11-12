import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/update_service.dart';

void main() {
  group('Official website update URL validation', () {
    test('accepts an APK hosted by honarmardomi.ir over HTTPS', () {
      expect(UpdateService.trusted('https://honarmardomi.ir/wp-content/uploads/payamyar-releases/PayamYar-1.4.2.apk'), isTrue);
    });
    test('accepts ZIP file served directly from the official host', () {
      expect(UpdateService.trusted('https://www.honarmardomi.ir/wp-content/uploads/payamyar-releases/PayamYar-1.4.2.zip'), isTrue);
    });
    test('rejects GitHub or external hosting', () {
      expect(UpdateService.trusted('https://github.com/example/PayamYar.apk'), isFalse);
      expect(UpdateService.trusted('https://honarmardomi.ir.evil.example/update.apk'), isFalse);
      expect(UpdateService.trusted('http://honarmardomi.ir/app.apk'), isFalse);
    });
    test('rejects links disguised as files and nonstandard ports', () {
      expect(UpdateService.trusted('https://honarmardomi.ir/update.html'), isFalse);
      expect(UpdateService.trusted('https://honarmardomi.ir:8080/app.apk'), isFalse);
      expect(UpdateService.trusted('https://user:pass@honarmardomi.ir/app.apk'), isFalse);
    });
  });
}
