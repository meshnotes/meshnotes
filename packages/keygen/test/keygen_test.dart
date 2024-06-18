import 'package:keygen/keygen.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    setUp(() {
      // Additional setup goes here.
    });

    test('Generate an ECDSA key', () {
      final signing = SigningWrapper.random();
      // String expectedResult = 'rsa_key';
      // expect(rsa.get(), expectedResult);
      print('PrivateKey: ${signing.getPrivateKey()}\nPublicKey: ${signing.getPublicKey()}\nCompressedPublicKey: ${signing.getCompressedPublicKey()}');
    });

    test('Load an ECDSA key', () {
      final keyStr = '9c5b1b530ff2750d85568d1ad0b6d9be3f5cd51ebefea481dbd23d5198fa9092';
      var key = SigningWrapper.loadKey(keyStr);
      expect(key.getPrivateKey(), keyStr);
      print('PrivateKey: ${key.getPrivateKey()}\nPublicKey: ${key.getCompressedPublicKey()}');
    });

    test('Test public key', () {
      var signing = SigningWrapper.random();
      var publicKeyStr = signing.getCompressedPublicKey();
      var verifying = VerifyingWrapper.loadKey(publicKeyStr);
      expect(publicKeyStr, verifying.getCompressedPublicKey());
      print('PublicKey: $publicKeyStr\nCompressedPublicKey: ${verifying.getCompressedPublicKey()}(PublicKey: ${verifying.getPublicKey()})');
    });

    test('Signing and verifying a text', () {
      var signing = SigningWrapper.random();
      var plainText = 'Hello123';
      var signature = signing.sign(plainText);
      print('Signature: $signature');

      var verifying = VerifyingWrapper.loadKey(signing.getCompressedPublicKey());
      print(verifying.ver(plainText, signature));
    });
  });
}
