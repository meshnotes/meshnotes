import 'package:flutter/material.dart';

/// Used by PluginInstance. This is the only way for PluginInstance to interact with MeshNotes app
abstract class PluginProxy {
  void registerPlugin(PluginRegisterInformation registerInformation);
  void showDialog(String title, Widget child);
  String getSelectedContent();
  String? getSettingValue(String key);
}

abstract class PluginInstance {
  void initPlugin(PluginProxy proxy);
  void start();
}

class PluginRegisterInformation {
  ToolbarInformation toolbarInformation;

  PluginRegisterInformation({
    required this.toolbarInformation,
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