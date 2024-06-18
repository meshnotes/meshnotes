import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'util.dart';

class HashUtil {
  static String hashBytes(List<int> bin) {
    final digest = sha256.convert(bin);
    return bytes2Hex(digest.bytes);
  }

  static String hashText(String text) {
    final bin = utf8.encode(text);
    return hashBytes(bin);
  }
}