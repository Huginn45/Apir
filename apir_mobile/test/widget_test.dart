import 'package:flutter_test/flutter_test.dart';
import 'package:apir_mobile/models/pairing_payload.dart';

void main() {
  test('Parses valid Apir QR pairing JSON payload', () {
    const raw =
        '{"app":"apir","uri":"ws://192.168.1.42:8765","host":"PRESENTER-PC","token":"4829"}';
    final parsed = PairingPayload.tryParseRaw(raw);
    expect(parsed, isNotNull);
    expect(parsed!.app, equals('apir'));
    expect(parsed.uri, equals('ws://192.168.1.42:8765'));
    expect(parsed.host, equals('PRESENTER-PC'));
    expect(parsed.token, equals('4829'));
  });

  test('Rejects non-apir QR payload', () {
    const raw = '{"app":"other","uri":"ws://192.168.1.42:8765","token":"1234"}';
    final parsed = PairingPayload.tryParseRaw(raw);
    expect(parsed, isNull);
  });
}
