import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:my_log/my_log.dart';

enum SettingType {
  string,
  number,
  bool,
}
class SettingData {
  final String name;
  String? displayName;
  String? value;
  String? comment;
  SettingType type;
  String defaultValue;


  SettingData({
    required this.name,
    this.displayName,
    this.value,
    this.comment,
    this.type = SettingType.string,
    this.defaultValue = '',
  }) {
    if(value == '') {
      value = defaultValue;
    }
  }
  SettingData clone() {
    return SettingData(name: name, displayName: displayName, value: value, comment: comment, type: type, defaultValue: defaultValue);
  }
}

class Setting {
  String settingFileName;
  // Single object
  // static Setting defaultSetting = Setting();
  Setting(String fileName): settingFileName = fileName;

  // block handler
  double blockHandlerSize = 16.0; // Size of block handler
  Color blockHandlerColor = Colors.grey; // Color of block handler
  Color blockHandlerDefaultBackgroundColor = Colors.transparent; // Background color of block handler in normal state
  Color blockHandlerHoverBackgroundColor = Colors.grey[200]!; // Background color of block handler in hover state

  // block extra tips icon
  double blockExtraTipsSize = 18.0; // Size of extra tips icon

  // block
  double blockNormalFontSize = 16.0; // 普通文本的字体大小
  double blockTitleFontSize = 32.0; // 标题文本的字体大小
  double blockHeadline1FontSize = 24; // headline1的字体大小
  double blockHeadline2FontSize = 20; // headline2的字体大小
  double blockHeadline3FontSize = 18; // headline3的字体大小
  double blockNormalLineHeight = 21.0; // 普通文本的行高
  int blockMaxCharacterLength = 1000; // 每个block最大字符数量

  // editor title
  EdgeInsets titleTextPadding = const EdgeInsets.fromLTRB(5, 15, 5, 15);
  Color titleSlashColor = Colors.grey;

  // toolbar button
  Color toolbarButtonDefaultBackgroundColor = Colors.transparent;
  Color toolbarButtonHoverBackgroundColor = Colors.grey[200]!;
  Color toolBarButtonTriggerOnColor = Colors.grey[400]!;

  // Changeable settings
  final Map<String, SettingData> _settingMap = {};
  final List<SettingData> _settingsSupported = [
    SettingData(
      name: Constants.settingKeyServerList,
      displayName: Constants.settingNameServerList,
      comment: Constants.settingCommentServerList,
      defaultValue: Constants.settingDefaultServerList,
    ),
    SettingData(
      name: Constants.settingKeyLocalPort,
      displayName: Constants.settingNameLocalPort,
      comment: Constants.settingCommentLocalPort,
      type: SettingType.number,
      defaultValue: Constants.settingDefaultLocalPort,
    ),
    SettingData(
      name: Constants.settingKeyUserInfo,
      displayName: Constants.settingNameUserInfo,
      comment: Constants.settingCommentUserInfo,
    ),
    SettingData( //TODO should use more precise privilege control mechanism, instead of this global setting
      name: Constants.settingKeyAllowSendingNotesToPlugins,
      displayName: Constants.settingNameAllowSendingNotesToPlugins,
      comment: Constants.settingCommentAllowSendingNotesToPlugins,
      defaultValue: Constants.settingDefaultAllowSendingNotesToPlugins,
      type: SettingType.bool,
    ),
  ];

  void load() {
    _settingMap.clear();
    for(final item in _settingsSupported) {
      _settingMap[item.name] = item;
    }
    var file = File(settingFileName);
    if(file.existsSync()) {
      var settings = _getSettingsFromFile(file);
      for(final e in settings.entries) {
        final key = e.key;
        final value = e.value;
        final oldSetting = _settingMap[key];
        if(oldSetting == null) {
          _settingMap[key] = SettingData(name: key, value: value);
        } else {
          oldSetting.value = value;
        }
      }
    }
  }
  static Map<String, String> _getSettingsFromFile(File file) {
    Map<String, String> result = {};
    var lines = file.readAsLinesSync();
    MyLogger.debug('_getSettingsFromFile: lines=$lines');
    for(var line in lines) {
      var (key, value) = _parseLine(line);
      if(key == null || value == null) continue;
      result[key] = value;
    }
    return result;
  }
  static (String?, String?) _parseLine(String line) {
    int idx = line.indexOf('=');
    if(idx == -1) {
      return (null, null);
    }
    String key = line.substring(0, idx).trim();
    String value = line.substring(idx + 1).trim();
    return (key, value);
  }

  List<SettingData> getSettings() {
    var result = <SettingData>[];
    for(final e in _settingMap.entries) {
      final value = e.value;
      if(value.displayName != null && value.comment != null) {
        result.add(value.clone());
      }
    }
    MyLogger.debug('getSettings: result=$result');
    return result;
  }
  // Return trimmed value of setting or default value, or null if not found
  String? getSetting(String key) {
    final setting = _settingMap[key];
    var value = setting?.value;
    if(value == null || value.isEmpty) {
      value = setting?.defaultValue;
    }
    return value?.trim();
  }
  bool saveSettings(List<SettingData> settings) {
    var toBeSave = <String, String>{};
    for(var item in settings) {
      final key = item.name;
      final value = item.value;
      if(!_settingMap.containsKey(key) || value == null) continue;
      _settingMap[key] = item;
      toBeSave[item.name] = value;
    }
    String content = _genSettingLines(_settingMap);
    File(settingFileName).writeAsStringSync(content);
    return true;
  }
  static String _genSettingLines(Map<String, SettingData> settings) {
    String result = '';
    for(var e in settings.entries) {
      final name = e.key;
      final value = e.value.value;
      if(value != null) {
        result += '$name = $value\n';
      }
    }
    return result;
  }
  void addAdditionalSettings(List<SettingData> settings) {
    for(var item in settings) {
      bool valid = true;
      for(var supported in _settingsSupported) {
        if(item.name == supported.name) {
          MyLogger.debug('addSupportedSettings: conflict setting, name=${item.name}');
          valid = false;
          break;
        }
      }
      if(valid) {
        _settingsSupported.add(item);
      }
    }
  }
}