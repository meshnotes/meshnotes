import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

class Util {
  static int getTimeStamp() {
    return DateTime.now().millisecondsSinceEpoch;
  }
  static int getRandom(int max) {
    return Random().nextInt(max);
  }

  static void runInPostFrame(Function() callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      callback();
    });
  }
}

class ClipboardUtil {
  static Future<void> writeToClipboard(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
  }
}