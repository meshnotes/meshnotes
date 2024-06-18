import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import '../setting/constants.dart';

class Environment {
  bool isDesktop() {
    return isWindows() || isMac() || isLinux();
  }
  bool isWindows() {
    return Platform.isWindows;
  }
  bool isMac() {
    return Platform.isMacOS;
  }
  bool isLinux() {
    return Platform.isLinux;
  }

  bool isMobile() {
    return isAndroid() || isIos();
  }
  bool isAndroid() {
    return Platform.isAndroid;
  }
  bool isIos() {
    return Platform.isIOS;
  }

  bool isSmallView(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return screenWidth <= Constants.widthThreshold;
  }
}