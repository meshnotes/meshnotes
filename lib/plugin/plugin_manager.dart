import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/editor_controller.dart';
import 'package:mesh_note/mindeditor/setting/setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/toolbar_button.dart';
import 'package:mesh_note/plugin/ai/plugin_ai.dart';
import 'package:my_log/my_log.dart';
import '../mindeditor/controller/controller.dart';
import '../mindeditor/setting/constants.dart';
import '../mindeditor/view/toolbar/appearance_setting.dart';
import 'plugin_api.dart';

List<PluginInstance> _plugins = [
  PluginAI(),
];

class PluginManager {
  List<ToolbarInformation> toolbarInfo = [];
  BuildContext? _context;
  OverlayEntry? _overlayEntry;
  final List<SettingData> _pluginSupportedSettings = [];
  final Map<PluginProxy, PluginRegisterInformation> _pluginInstances = {};

  void initPluginManager() {
    for(var plugin in _plugins) {
      var _pluginProxy = PluginProxyImpl(this);
      plugin.initPlugin(_pluginProxy);
      _pluginProxy.init(plugin);
    }

    for(var plugin in _plugins) {
      plugin.start();
    }
  }

  void updateContext(BuildContext context) {
    _context = context;
  }

  /// Register plugin
  /// 1. Add plugin toolbar
  /// 2. Add plugin settings
  void registerPlugin(PluginProxyImpl proxy, PluginRegisterInformation pluginInfo) {
    if(_pluginInstances.containsKey(proxy)) return; // Duplicated

    _pluginInstances[proxy] = pluginInfo;
    toolbarInfo.add(pluginInfo.toolbarInformation);
    for(var setting in pluginInfo.settingsInformation) {
      _addToSupportedSetting(pluginInfo.pluginName, setting);
    }
  }
  void _addToSupportedSetting(String pluginName, PluginSetting setting) {
    // Add prefix to the key, check duplication, and add the setting item
    String key = '${Constants.settingKeyPluginPrefix}/$pluginName/${setting.settingKey}';
    for(var item in _pluginSupportedSettings) {
      if(item.name == key) {
        MyLogger.warn('Duplicated plugin key: $key');
        return;
      }
    }
    SettingData settingData = SettingData(
      name: key,
      displayName: setting.settingName,
      comment: setting.settingComment,
      defaultValue: setting.settingDefaultValue,
    );
    _pluginSupportedSettings.add(settingData);
  }

  List<Widget> buildButtons({
    required AppearanceSetting appearance,
    required Controller controller,
  }) {
    var result = <Widget>[];
    for(var item in toolbarInfo) {
      var button = ToolbarButton(
        icon: Icon(item.buttonIcon),
        appearance: appearance,
        tip: item.tip,
        controller: controller,
        onPressed: item.action,
      );
      result.add(button);
    }
    return result;
  }

  String getSelectedOrFocusedContent() {
    var content = Controller.instance.selectionController.getSelectedContent();
    if(content.isEmpty) {
      content = Controller.instance.getEditingBlockState()?.getPlainText()?? '';
    }
    return content;
  }
  String? getSettingValue(PluginProxyImpl proxy, String pluginKey) {
    if(!_pluginInstances.containsKey(proxy)) return null; // Check

    String pluginName = _pluginInstances[proxy]!.pluginName;
    String key = '${Constants.settingKeyPluginPrefix}/$pluginName/$pluginKey';
    return Controller.instance.setting.getSetting(key);
  }
  void sendTextToClipboard(String text) {
    //TODO should add toast notification while finished
    EditorController.copyTextToClipboard(text);
  }
  String? appendTextToNextBlock(String blockId, String text) {
    var blockState = Controller.instance.getBlockState(blockId);
    if(blockState == null) return null;

    text = text.replaceAll('\r', '');
    var splitTexts = text.split('\n');
    var blockIds = blockState.appendBlocksWithTexts(splitTexts);
    CallbackRegistry.refreshDoc();
    return blockIds.isEmpty? null: blockIds[blockIds.length - 1];
  }

  String? getEditingBlockId() {
    return Controller.instance.getEditingBlockId();
  }

  void closeDialog() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
  void showDialog(String title, Widget subChild) {
    if(_context == null) return;

    if(_overlayEntry != null) {
      closeDialog();
    }
    CallbackRegistry.hideKeyboard();
    final smallView = Controller.instance.environment.isSmallView(_context!);
    _overlayEntry = OverlayEntry(
      builder: (context) {
        double width = 300;
        double height = 300;
        if(smallView) {
          width = double.infinity;
          height = double.infinity;
        }
        var child = Container(
          child: subChild,
        );
        var titleBar = _buildTitleBar(title);
        var column = Column(
          children: [
            titleBar,
            Expanded(
              child: child,
            ),
          ],
        );
        var dialog = Scaffold(
          // elevation: 32.0,
          // type: MaterialType.transparency,
          body: Container(
            padding: const EdgeInsets.all(8.0),
            child: column,
          ),
        );
        var box = SizedBox(
          width: width,
          height: height,
          child: dialog,
        );
        // double horizonPadding = 8.0;
        // double verticalPadding = Controller.instance.getToolbarHeight()?? 16.0;
        var container = Container(
          margin: const EdgeInsets.fromLTRB(0, 128, 0, 0),
          alignment: Alignment.bottomRight,
          child: Material(
            elevation: 1.0,
            child: box,
          ),
        );
        // var align = Align(
        //   alignment: Alignment.bottomRight,
        //   child: container,
        // );
        return container;
      }
    );
    Overlay.of(_context!).insert(_overlayEntry!);
  }

  List<SettingData> getPluginSupportedSettings() {
    return _pluginSupportedSettings;
  }
  Widget _buildTitleBar(String title) {
    var titleText = Text(title);
    var button = CupertinoButton(
      child: const Icon(Icons.close),
      onPressed: closeDialog,
    );
    var row = Row(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: titleText,
        ),
        const Spacer(),
        Align(
          alignment: Alignment.centerRight,
          child: button,
        ),
      ],
    );
    return row;
  }
}

class PluginProxyImpl implements PluginProxy {
  final PluginManager _manager;
  late final PluginInstance _instance;

  PluginProxyImpl(PluginManager pluginManager): _manager = pluginManager;
  PluginInstance getInstance() => _instance;

  void init(PluginInstance instance) => _instance = instance;

  @override
  void registerPlugin(PluginRegisterInformation pluginRegisterInfo) {
    _manager.registerPlugin(this, pluginRegisterInfo);
  }

  @override
  void showDialog(String title, Widget child) {
    _manager.showDialog(title, child);
  }

  @override
  String getSelectedOrFocusedContent() {
    return _manager.getSelectedOrFocusedContent();
  }

  @override
  String? getSettingValue(String key) {
    return _manager.getSettingValue(this, key);
  }

  @override
  String? getEditingBlockId() {
    return _manager.getEditingBlockId();
  }

  @override
  void sendTextToClipboard(String text) {
    return _manager.sendTextToClipboard(text);
  }

  @override
  String? appendTextToNextBlock(String blockId, String text) {
    return _manager.appendTextToNextBlock(blockId, text);
  }
}