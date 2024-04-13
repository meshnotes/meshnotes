/// Used by PluginInstance. This is the only way for PluginInstance to interact with MeshNotes app
abstract class PluginProxy {
  void registerPlugin();
}

abstract class PluginInstance {
  void initPlugin(PluginProxy proxy);
  void start();
}