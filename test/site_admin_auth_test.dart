import 'package:flutter_test/flutter_test.dart';
import 'package:payamyar/security/vault.dart';
import 'package:payamyar/site_admin_auth.dart';

void main() {
  test('site admin access never defaults to true for unpaired users', () async {
    await SiteAdminAuth.unlink();
    expect(await SiteAdminAuth.paired(), false);
    expect(await SiteAdminAuth.authorized(), false);
  });
  test('pair rejects malformed codes without making a network request', () async {
    await SiteAdminAuth.unlink();
    final error = await SiteAdminAuth.link('bad-code');
    expect(error, isNotNull);
    expect(await SiteAdminAuth.paired(), false);
    expect(await Vault.get('honar_site_admin_token'), isNull);
  });
}
