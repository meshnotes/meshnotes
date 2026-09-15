import 'package:libp2p/application/version_chain_api.dart';
import 'package:test/test.dart';

import 'dart:convert';

void main() {
  test('BroadcastMessages signable string is stable across signature and json round trip', () {
    final message = BroadcastMessages(
      type: versionChainBroadcastType,
      userPublicId: 'owner',
      signature: '',
      messages: {
        'latest_version': 'v1',
        'latest_version_timestamp': '123',
      },
    );

    final signableBeforeSigning = message.toSignableString();
    message.signature = 'signature-1';
    final signedJson = jsonEncode(message);
    final decodedMessage = BroadcastMessages.fromJson(jsonDecode(signedJson));

    expect(decodedMessage.signature, 'signature-1');
    expect(decodedMessage.toSignableString(), signableBeforeSigning);

    decodedMessage.signature = 'signature-2';
    expect(decodedMessage.toSignableString(), signableBeforeSigning);
  });
}
