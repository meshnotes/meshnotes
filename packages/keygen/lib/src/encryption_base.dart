import 'dart:convert';
import 'package:elliptic/elliptic.dart';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class EncryptWrapper {
  PrivateKey key;
  EncryptWrapper({
    required this.key,
  });

  Uint8List _genUint8List(int value) {
    List<int> list = List.filled(8, 0);
    for(int i = 0; i < 8; i++) {
      list[i] = value & 0xFF;
      value >>= 8;
    }
    return Uint8List.fromList(list);
  }
  (Encrypter, IV) _genEncrypter(int timestamp) {
    final keyText = key.toString() + timestamp.toString();
    final keyInt = keyText.codeUnits;
    final digest = sha256.convert(keyInt);
    final digestBase64 = base64Encode(digest.bytes);
    final aesKey = Key.fromBase64(digestBase64);

    final en = Encrypter(AES(aesKey));
    final iv = IV(_genUint8List(timestamp));
    return (en, iv);
  }

  String encrypt(int timestamp, String text) {
    var (en, iv) = _genEncrypter(timestamp);

    final encrypted = en.encrypt(text, iv: iv);
    return encrypted.base64;
  }

  String decrypt(int timestamp, String text) {
    var (en, iv) = _genEncrypter(timestamp);

    final encrypted = Encrypted.fromBase64(text);
    final decrypted = en.decrypt(encrypted, iv: iv);
    return decrypted;
  }
}

class AesWrapper {
  final Encrypter encrypter;
  final IV iv;

  AesWrapper({
    required password,
    required int randomNumber,
  }): encrypter = _buildEncrypter(password),
      iv = _generateIV(randomNumber, randomNumber);

  static Encrypter _buildEncrypter(String password) {
    final key = Key.fromUtf8(password.padRight(32, '0').substring(0, 32));
    return Encrypter(AES(key));
  }

  static IV _generateIV(int randomNumber1, int randomNumber2) {
    final ivBytes = Uint8List.fromList(
      List.generate(16, (i) => i < 8 
        ? (randomNumber1 >> (i * 8)) & 0xFF
        : (randomNumber2 >> ((i - 8) * 8)) & 0xFF)
    );
    return IV(ivBytes);
  }

  String encrypt(String text) {
    final encrypted = encrypter.encrypt(text, iv: iv);
    return encrypted.base64;
  }

  String decrypt(String encryptedText) {
    final encrypted = Encrypted.fromBase64(encryptedText);
    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    return decrypted;
  }
}
