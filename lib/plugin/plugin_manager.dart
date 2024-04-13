import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/toolbar_button.dart';
import 'package:my_log/my_log.dart';

import '../mindeditor/controller/controller.dart';
import '../mindeditor/view/toolbar/appearance_setting.dart';
import 'plugin_api.dart';

List<PluginInstance> _plugins = [
];
class PluginManager {
  late PluginProxy _pluginProxy;

  void initPluginManager() {
    _pluginProxy = PluginProxyImpl();

    for(var plugin in _plugins) {
      plugin.initPlugin(_pluginProxy);
    }

    for(var plugin in _plugins) {
      plugin.start();
    }
  }

  List<Widget> buildButtons({
    required AppearanceSetting appearance,
    required Controller controller,
  }) {
    var button = ToolbarButton(
      icon: const Icon(Icons.wb_incandescent_outlined),
      appearance: appearance,
      tip: 'AI',
      controller: controller,
      onPressed: () {
        MyLogger.info('AI button pressed');
      },
    );
    return [button];
  }
}

class PluginProxyImpl implements PluginProxy {
  @override
  void registerPlugin() {
    // TODO: implement registerPlugin
  }
}