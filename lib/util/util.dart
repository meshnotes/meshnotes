import 'dart:math';

class Util {
  static int getTimeStamp() {
    return DateTime.now().millisecondsSinceEpoch;
  }
  static int getRandom(int max) {
    return Random().nextInt(max);
  }
}