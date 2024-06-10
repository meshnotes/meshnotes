import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:my_log/my_log.dart';
import '../controller/controller.dart';

class SettingData {
  final String name;
  final String displayName;
  String value;
  final String comment;
  final bool isNumber;
  String defaultValue;


  SettingData({
    required this.name,
    required this.displayName,
    this.value = '',
    required this.comment,
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
  // Single object
  static Setting defaultSetting = Setting();

  // block handler
  double blockHandlerSize = 16.0; // 抓手的大小
  Color blockHandlerColor = Colors.grey; // 抓手的颜色
  Color blockHandlerDefaultBackgroundColor = Colors.transparent; // 抓手默认状态下的背景颜色
  Color blockHandlerHoverBackgroundColor = Colors.grey[200]!; // 抓手hover状态下的背景颜色

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

  void loadFromDb(DbHelper db) {
    _settingMap.clear();
    for(final item in _settingsSupported) {
      _settingMap[item.name] = item;
    }
    var settings = db.getSettings();
    for(final key in settings.keys) {
      if(!_settingMap.containsKey(key)) continue;
      _settingMap[key]!.value = settings[key]??'';
    }
  }

  List<SettingData> getSettings() {
    var result = <SettingData>[];
    for(final key in _settingMap.keys) {
      result.add(_settingMap[key]!.clone());
    }
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
      final name = item.name;
      if(!_settingMap.containsKey(name)) continue;
      _settingMap[name] = item;
      toBeSave[item.name] = item.value;
    }
    Controller.instance.dbHelper.saveSettings(toBeSave);
    return true;
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