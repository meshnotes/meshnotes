import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:elliptic/elliptic.dart';
import 'package:ecdsa/ecdsa.dart';

final EllipticCurve _ec = getP256();

PrivateKey genRandomKey() {
  var privateKey = _ec.generatePrivateKey();
  return privateKey;
}

class SigningWrapper {

  PrivateKey key;

  SigningWrapper({
    required this.key,
  });
  SigningWrapper.random(): key = genRandomKey();

  factory SigningWrapper.loadKey(String hex) {
    final key = PrivateKey.fromHex(_ec, hex);
    return SigningWrapper(key: key);
  }


  String sign(String text) {
    // var hash = List<int>.generate(text.length ~/ 2,
    //         (i) => int.parse(text.substring(i * 2, i * 2 + 2), radix: 16));
    var hash = utf8.encode(text);
    var sig = signature(key, hash);
    // print('compact hex: ${sig.toCompactHex()}');
    // print('string: ${sig.toString()}');
    // print('list: ${sig.toCompact()}');
    var bin = sig.toCompact();
    return base64Encode(bin);
  }
  String getPublicKey() {
    return key.publicKey.toString();
  }
  String getCompressedPublicKey() {
    return key.publicKey.toCompressedHex();
  }
  String getPrivateKey() {
    return key.toString();
  }
}

class VerifyingWrapper {
  PublicKey key;
  VerifyingWrapper({
    required this.key,
  });

  factory VerifyingWrapper.loadKey(String hex) {
    final key = PublicKey.fromHex(_ec, hex);
    return VerifyingWrapper(key: key);
  }

  bool ver(String textOriginal, String textSignature) {
    // var sig = List<int>.generate(textSignature.length ~/ 2,
    //         (i) => int.parse(textSignature.substring(i * 2, i * 2 + 2), radix: 16));
    var hash = utf8.encode(textOriginal);
    var bin = base64Decode(textSignature);
    return verify(key, hash, Signature.fromCompact(bin));
  }
  String getPublicKey() {
    return key.toString();
  }
  String getCompressedPublicKey() {
    return key.toCompressedHex();
  }
}

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