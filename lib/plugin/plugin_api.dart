import 'package:flutter/material.dart';

import 'user_notes_for_plugin.dart';

/// Used by PluginInstance. This is the only way for PluginInstance to interact with MeshNotes app
abstract class PluginProxy {
  // Plugin register
  void registerEditorPlugin(EditorPluginRegisterInformation registerInformation);
  void registerGlobalPlugin(GlobalPluginRegisterInformation registerInformation);

  // Followings are all interface for plugin to show UI
  // Plugin request to show a dialog
  void showDialog(String title, Widget child);
  // Plugin request to close (all) dialogs
  void closeDialog();

  // Plugin request to show a toast
  void showToast(String message);

  // Document content functions
  String getSelectedOrFocusedContent();
  String? getEditingBlockId();
  void sendTextToClipboard(String text);
  UserNotes? getUserNotes();
  List<DocumentMeta> getAllDocumentList();
  String getDocumentContent(String documentId);

  // Document editing functions
  void addExtra(String blockId, String content);
  void clearExtra(String blockId);
  bool createNote(String title, String content);
  String? appendTextToNextBlock(String blockId, String text);
  void appendToDocument(String documentId, String content);

  // Global functions
  String? getSettingValue(String key);
  Platform getPlatform();
  bool openDocument(String documentId);
}

abstract class PluginInstance {
  void initPlugin(PluginProxy proxy);
  void start();
}

class EditorPluginRegisterInformation {
  String pluginName;
  ToolbarInformation toolbarInformation;
  List<PluginSetting> settingsInformation;
  void Function(BlockChangedEventData)? onBlockChanged;

  EditorPluginRegisterInformation({
    required this.pluginName,
    required this.toolbarInformation,
    required this.settingsInformation,
    this.onBlockChanged,
  });
}

class GlobalPluginRegisterInformation {
  String pluginName;
  GlobalToolbarInformation toolbarInformation;
  List<PluginSetting> settingsInformation;

  GlobalPluginRegisterInformation({
    required this.pluginName,
    required this.toolbarInformation,
    required this.settingsInformation,
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

class GlobalToolbarInformation {
  IconData buttonIcon;
  Widget? Function({required void Function() onClose}) buildWidget;
  String tip;
  final bool Function() isAvailable;

  GlobalToolbarInformation({
    required this.buttonIcon,
    required this.buildWidget,
    required this.tip,
    required this.isAvailable,
  });
}

enum PluginSettingType {
  string,
  number,
  bool,
}
class PluginSetting {
  String settingKey;
  String settingName;
  String settingComment;
  String settingDefaultValue;
  PluginSettingType type;

  PluginSetting({
    required this.settingKey,
    required this.settingName,
    required this.settingComment,
    this.settingDefaultValue = '',
    this.type = PluginSettingType.string,
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

abstract class Platform {
  bool isWindows();
  bool isMacOS();
  bool isAndroid();
  bool isIOS();
  bool isMobile();
  bool isLinux();
}