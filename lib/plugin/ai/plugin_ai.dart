import 'package:mesh_note/plugin/plugin_api.dart';

class PluginAI implements PluginInstance {
  late PluginProxy _proxy;

  @override
  void initPlugin(PluginProxy proxy) {
    _proxy = proxy;
    proxy.registerPlugin();
  }

  @override
  void start() {
    // TODO: implement start
  }

}