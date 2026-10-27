import 'package:couple_app/core/push/push_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('push token ids are short, stable and valid document ids', () {
    const token = 'dXk2:APA91bH-abc_DEF123'
        'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
        'yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy';
    final id = PushService.tokenId(token);
    expect(id, PushService.tokenId(token));
    expect(id, matches(RegExp(r'^p[0-9a-f]{16}$')));
    expect(PushService.tokenId('$token!'), isNot(id));
  });

  test('push is skipped where Firebase is not set up (tests)', () async {
    await PushService.instance.start('someone');
    await PushService.instance.stop();
  });
}
