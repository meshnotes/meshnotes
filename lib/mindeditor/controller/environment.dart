import 'dart:io' show File, Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';
import '../setting/constants.dart';

class Environment {
  /// Set from [IosDeviceInfo] during app init. True when the **device** is an iPad (hardware/simulator id), not derived from window [MediaQuery] size — needed because Stage Manager window width can be narrow while still on iPad.
  bool iosReportsAsPad = false;

  /// First segment of [IosDeviceInfo.systemVersion] on iOS (e.g. 26 from `26.0.1`). Stays 0 before init or on non‑iOS. Used to gate iPad window-caption workarounds that only apply from iPadOS 26 onward.
  int iosSystemMajorVersion = 0;

  /// Derives [iosReportsAsPad] and [iosSystemMajorVersion] from [data]. Call once after [DeviceInfoPlugin.iosInfo] during startup.
  void applyIosDeviceInfo(IosDeviceInfo data) {
    iosReportsAsPad = _iosDeviceInfoIsPad(data);
    iosSystemMajorVersion = _iosMajorVersionFromSystemVersion(data.systemVersion);
  }

  static bool _iosDeviceInfoIsPad(IosDeviceInfo i) {
    final String machine = i.utsname.machine.toLowerCase();
    if(machine.contains('ipad')) return true;
    return i.model.toLowerCase() == 'ipad';
  }

  static int _iosMajorVersionFromSystemVersion(String systemVersion) {
    final int dot = systemVersion.indexOf('.');
    final String head = dot < 0 ? systemVersion : systemVersion.substring(0, dot);
    return int.tryParse(head) ?? 0;
  }

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

  Future<String> getLogPath() async {
    final dir = (await getLibraryPathsByEnvironment())[0];
    return '$dir/log';
  }
  Future<List<String>> getLibraryPathsByEnvironment() async {
    if(isWindows() || isLinux() || isMac()) {
      return [
        File(Platform.script.toFilePath()).parent.path,
        File(Platform.resolvedExecutable).parent.path,
      ];
    }
    final dir = await getApplicationDocumentsDirectory();
    return [dir.path];
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