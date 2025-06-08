import 'dart:convert';

import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:my_log/my_log.dart';

class EncryptedUserPrivateInfo {
  String publicKey;
  String userName;
  String privateKey;
  int timestamp;
  String signature;
  bool isEncrypted;

  EncryptedUserPrivateInfo({
    required this.publicKey,
    required this.userName,
    required this.privateKey,
    required this.timestamp,
    this.signature = '',
    this.isEncrypted = false,
  });

  String getFeature() {
    return 'public_key: $publicKey\n'
        'name: $userName\n'
        'private_key: $privateKey\n'
        'timestamp: $timestamp\n';
  }

  EncryptedUserPrivateInfo.fromJson(Map<String, dynamic> map):
        publicKey = map['public_key'],
        userName = map['name'],
        privateKey = map['private_key'],
        timestamp = map['timestamp'],
        signature = map['sign'],
        isEncrypted = map['encrypted']?? false;

  Map<String, dynamic> toJson() {
    return {
      'public_key': publicKey,
      'name': userName,
      'private_key': privateKey,
      'timestamp': timestamp,
      'sign': signature,
      'encrypted': isEncrypted,
    };
  }

  factory EncryptedUserPrivateInfo.fromBase64(String str) {
    final bytes = base64Decode(str.trim());
    final json = utf8.decode(bytes);
    return EncryptedUserPrivateInfo.fromJson(jsonDecode(json));
  }
  String toBase64() {
    final json = jsonEncode(this);
    final base64 = base64Encode(utf8.encode(json));
    return base64;
  }

  factory EncryptedUserPrivateInfo.fromSimpleUserPrivateInfoAndPassword(SimpleUserPrivateInfo simpleUserInfo, String password) {
    final name = simpleUserInfo.userName;
    final publicKey = simpleUserInfo.publicKey;
    final privateKey = simpleUserInfo.privateKey;
    final timestamp = simpleUserInfo.timestamp;
    if(password.isEmpty) {
      return EncryptedUserPrivateInfo(publicKey: publicKey, userName: name, privateKey: privateKey, timestamp: timestamp, isEncrypted: false);
    }
    
    MyLogger.debug('Encrypting private key with password: $password');
    final encrypt = AesWrapper(password: password, randomNumber: timestamp);
    final encryptedPrivateKey = encrypt.encrypt(privateKey);
    return EncryptedUserPrivateInfo(publicKey: publicKey, userName: name, privateKey: encryptedPrivateKey, timestamp: timestamp, isEncrypted: true);
  }

  SimpleUserPrivateInfo? getSimpleUserPrivateInfo(String password) {
    final name = userName;
    final publicKey = this.publicKey;
    final timestamp = this.timestamp;
    if(!isEncrypted) {
      return SimpleUserPrivateInfo(publicKey: publicKey, userName: name, privateKey: privateKey, timestamp: timestamp);
    }

    MyLogger.debug('Decrypting private key with password: $password');
    try {
      final encrypt = AesWrapper(password: password, randomNumber: timestamp);
      final decryptedPrivateKey = encrypt.decrypt(privateKey);
      return SimpleUserPrivateInfo(publicKey: publicKey, userName: name, privateKey: decryptedPrivateKey, timestamp: timestamp);
    } catch(e) {
      MyLogger.warn('Error decrypting private key: $e');
      return null;
    }
  }
}