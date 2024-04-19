import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/toolbar_button.dart';
import 'package:mesh_note/plugin/ai/plugin_ai.dart';
import '../mindeditor/controller/controller.dart';
import '../mindeditor/setting/constants.dart';
import '../mindeditor/view/toolbar/appearance_setting.dart';
import 'plugin_api.dart';

List<PluginInstance> _plugins = [
  PluginAI(),
];

class PluginManager {
  late PluginProxy _pluginProxy;
  List<ToolbarInformation> toolbarInfo = [];
  BuildContext? _context;
  OverlayEntry? _overlayEntry;

  void initPluginManager() {
    _pluginProxy = PluginProxyImpl(this);

    for(var plugin in _plugins) {
      plugin.initPlugin(_pluginProxy);
    }

    for(var plugin in _plugins) {
      plugin.start();
    }
  }

  void updateContext(BuildContext context) {
    _context = context;
  }

  void addPlugin(PluginRegisterInformation pluginInfo) {
    toolbarInfo.add(pluginInfo.toolbarInformation);
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

  String getSelectedContent() {
    return Controller.instance.selectionController.getSelectedContent();
  }
  String? getSettingValue(String pluginKey) {
    String key = '${Constants.settingKeyPluginPrefix}$pluginKey';
    return Controller.instance.setting.getSetting(key);
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
        var dialog = Material(
          elevation: 4.0,
          // type: MaterialType.transparency,
          child: column,
        );
        var box = SizedBox(
          width: width,
          height: height,
          child: dialog,
        );
        double horizonPadding = 32.0;
        double verticalPadding = Controller.instance.getToolbarHeight()?? 16.0;
        var container = Container(
          margin: EdgeInsets.fromLTRB(horizonPadding, verticalPadding, horizonPadding, verticalPadding),
          alignment: Alignment.bottomRight,
          child: box,
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

  PluginProxyImpl(PluginManager pluginManager): _manager = pluginManager;

  @override
  void registerPlugin(PluginRegisterInformation pluginRegisterInfo) {
    _manager.addPlugin(pluginRegisterInfo);
  }

  @override
  void showDialog(String title, Widget child) {
    _manager.showDialog(title, child);
  }

  @override
  String getSelectedContent() {
    return _manager.getSelectedContent();
  }

  @override
  String? getSettingValue(String key) {
    return _manager.getSettingValue(key);
  }
}