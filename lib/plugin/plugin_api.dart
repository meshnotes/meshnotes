import 'package:flutter/material.dart';

import 'user_notes_for_plugin.dart';

/// Used by PluginInstance. This is the only way for PluginInstance to interact with MeshNotes app
abstract class PluginProxy {
  // Plugin register
  void registerPlugin(PluginRegisterInformation registerInformation);

  // Followings are all interface for plugin to show UI
  // Plugin request to show a dialog
  void showDialog(String title, Widget child);
  // Plugin request to close (all) dialogs
  void closeDialog();
  // Plugin request to show a global dialog
  void showGlobalDialog(String title, Widget child);
  // Plugin request to close a global dialog
  void closeGlobalDialog();

  // Plugin request to show a toast
  void showToast(String message);

  String getSelectedOrFocusedContent();
  String? getSettingValue(String key);
  String? getEditingBlockId();
  void sendTextToClipboard(String text);
  String? appendTextToNextBlock(String blockId, String text);
  void addExtra(String blockId, String content);
  void clearExtra(String blockId);
  UserNotes? getUserNotes();
  bool createNote(String title, String content);
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