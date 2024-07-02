import 'package:flutter/material.dart';

/// Used by PluginInstance. This is the only way for PluginInstance to interact with MeshNotes app
abstract class PluginProxy {
  void registerPlugin(PluginRegisterInformation registerInformation);
  void showDialog(String title, Widget child);
  String getSelectedOrFocusedContent();
  String? getSettingValue(String key);
  String? getEditingBlockId();
  void sendTextToClipboard(String text);
  String? appendTextToNextBlock(String blockId, String text);
  void addExtra(String blockId, String content);
  void clearExtra(String blockId);
}

abstract class PluginInstance {
  void initPlugin(PluginProxy proxy);
  void start();
}

class PluginRegisterInformation {
  String pluginName;
  ToolbarInformation toolbarInformation;
  List<PluginSetting> settingsInformation;
  void Function(BlockChangedEventData)? onBlockChanged;

  PluginRegisterInformation({
    required this.pluginName,
    required this.toolbarInformation,
    required this.settingsInformation,
    this.onBlockChanged,
  });
}

class ToolbarInformation {
  IconData buttonIcon;
  void Function() action;
  String tip;

  ToolbarInformation({
    required this.buttonIcon,
    required this.action,
    required this.tip,
  });
}

class PluginSetting {
  String settingKey;
  String settingName;
  String settingComment;
  String settingDefaultValue;

  PluginSetting({
    required this.settingKey,
    required this.settingName,
    required this.settingComment,
    this.settingDefaultValue = '',
  });
}

class BlockChangedEventData {
  String blockId;
  String content;
  BlockChangedEventData({
    required this.blockId,
    required this.content,
  });
}