import 'package:nanoid/nanoid.dart';

class IdGen {
  static String getUid() {
    return nanoid();
  }
}