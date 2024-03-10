import 'package:keygen/keygen.dart';
import 'package:test/test.dart';

void main() {
  test('Encrypt and decrypt', () {
    final privateKey = genRandomKey();
    int timestamp = DateTime.now().millisecondsSinceEpoch;
    EncryptWrapper encryptWrapper = EncryptWrapper(key: privateKey);

    String plainText1 = 'Hello, this is a plain text';
    String plainText2 = 'Nice to meet you';

    final encryptedText1 = encryptWrapper.encrypt(timestamp, plainText1);
    final encryptedText2 = encryptWrapper.encrypt(timestamp, plainText2);

    print('After encrypted 1: $encryptedText1');
    print('After encrypted 2: $encryptedText2');

    EncryptWrapper decryptWrapper = EncryptWrapper(key: privateKey);
    final decryptedText2 = decryptWrapper.decrypt(timestamp, encryptedText2);
    final decryptedText1 = decryptWrapper.decrypt(timestamp, encryptedText1);

    print('After decrypted 1: $decryptedText1');
    print('After decrypted 2: $decryptedText2');

    expect(plainText1, decryptedText1);
    expect(plainText2, decryptedText2);
  });
}
