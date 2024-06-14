import 'dart:io' show File, Platform;
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
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

  List<String> getLibraryPaths() {
    return [
      File(Platform.script.toFilePath()).parent.path,
      File(Platform.resolvedExecutable).parent.path,
    ];
  }

  String getExistFileFromLibraryPaths(String fileName) {
    final lookupPaths = getLibraryPaths();
    String? firstChoicePath;
    for(var path in lookupPaths) {
      final fullPath = '$path/$fileName';
      firstChoicePath ??= fullPath;
      if(File(fullPath).existsSync()) {
        return fullPath;
      }
    }
    return firstChoicePath!;
  }

  Future<List<String>> getLibraryPathsByEnvironment() async {
    if(isWindows() || isLinux() || isMac()) {
      return [
        File(Platform.script.toFilePath()).parent.path,
        File(Platform.resolvedExecutable).parent.path,
      ];
    }
    return [getApplicationDocumentsDirectory().toString()];
  }
  Future<String> getExistFileFromLibraryPathsByEnvironment(String fileName) async {
    final lookupPaths = await getLibraryPathsByEnvironment();
    String? firstChoicePath;
    for(var path in lookupPaths) {
      final fullPath = '$path/$fileName';
      firstChoicePath ??= fullPath;
      if(File(fullPath).existsSync()) {
        return fullPath;
      }
    }
    return firstChoicePath!;
  }
}