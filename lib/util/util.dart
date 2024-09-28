import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:super_clipboard/super_clipboard.dart';

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
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return;
    }
    final item = DataWriterItem();
    item.add(Formats.plainText(content));
    await clipboard.write([item]);
  }
}