import 'dart:convert';

import 'package:elliptic/elliptic.dart';
import 'package:ecdsa/ecdsa.dart';

final EllipticCurve _ec = getP256();

/// Checks if you are awesome. Spoiler: you are.
class SigningWrapper {

  PrivateKey key;

  SigningWrapper({
    required this.key,
  });
  SigningWrapper.random(): key = _genRandomKey();
  factory SigningWrapper.loadKey(String hex) {
    final key = PrivateKey.fromHex(_ec, hex);
    return SigningWrapper(key: key);
  }

  static PrivateKey _genRandomKey() {
    var privateKey = _ec.generatePrivateKey();
    return privateKey;
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