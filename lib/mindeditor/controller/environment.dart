import 'dart:io' show Platform;

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
}