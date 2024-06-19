import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:my_log/my_log.dart';

class SettingData {
  final String name;
  String? displayName;
  String? value;
  String? comment;
  final bool isNumber;
  String defaultValue;


  SettingData({
    required this.name,
    this.displayName,
    this.value,
    this.comment,
    this.isNumber = false,
    this.defaultValue = '',
  }) {
    if(value == '') {
      value = defaultValue;
    }
  }
  SettingData clone() {
    return SettingData(name: name, displayName: displayName, value: value, comment: comment, isNumber: isNumber, defaultValue: defaultValue);
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
      isNumber: true,
      defaultValue: Constants.settingDefaultLocalPort,
    ),
    SettingData(
      name: Constants.settingKeyTest,
      displayName: Constants.settingNameTest,
      comment: Constants.settingCommentTest,
    ),
    SettingData(
      name: Constants.settingKeyUserInfo,
      displayName: Constants.settingNameUserInfo,
      comment: Constants.settingCommentUserInfo,
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
      for(final key in settings.keys) {
        if(!_settingMap.containsKey(key)) continue;
        _settingMap[key]!.value = settings[key]??'';
      }
    }
  }
  static Map<String, String> _getSettingsFromFile(File file) {
    Map<String, String> result = {};
    var lines = file.readAsLinesSync();
    MyLogger.info('efantest: lines=$lines');
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
  void loadFromDb(DbHelper db) {
    _settingMap.clear();
    for(final item in _settingsSupported) {
      _settingMap[item.name] = item;
    }
    var settings = db.getSettings();
    for(final e in settings.entries) {
      String key = e.key;
      String value = e.value;
      if(_settingMap.containsKey(key)) {
        _settingMap[key]!.value = value;
      } else {
        _settingMap[key] = SettingData(name: key, value: value);
      }
    }
  }

  List<SettingData> getSettings() {
    var result = <SettingData>[];
    for(final e in _settingMap.entries) {
      final value = e.value;
      if(value.displayName != null && value.comment != null) {
        result.add(value.clone());
      }
    }
    MyLogger.info('efantest: result=$result');
    return result;
  }
  String? getSetting(String key) {
    if (_settingMap.containsKey(key)) {
      final setting = _settingMap[key]!;
      return setting.value;
    }
    return null;
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