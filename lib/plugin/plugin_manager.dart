import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/editor_controller.dart';
import 'package:mesh_note/mindeditor/controller/environment.dart';
import 'package:mesh_note/mindeditor/setting/setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/toolbar_button.dart';
import 'package:mesh_note/plugin/ai/plugin_ai.dart';
import 'package:my_log/my_log.dart';
import '../mindeditor/controller/controller.dart';
import '../mindeditor/setting/constants.dart';
import '../mindeditor/view/toolbar/base/appearance_setting.dart';
import 'global_plugin_buttons_manager.dart';
import 'plugin_api.dart';
import 'user_notes_for_plugin.dart';

List<PluginInstance> _plugins = [
  PluginAI(),
];

class PluginManager {
  final List<ToolbarInformation> _editorToolbarInfo = [];
  final List<GlobalToolbarInformation> _globalToolbarInfo = [];
  final List<SettingData> _pluginSupportedSettings = [];
  final Map<PluginProxy, EditorPluginRegisterInformation> _editorPluginInstances = {};
  final Map<PluginProxy, GlobalPluginRegisterInformation> _globalPluginInstances = {};
  final controller = Controller();
  final _globalPluginButtonsManagerKey = GlobalKey<GlobalPluginButtonsManagerState>();
  GlobalPluginButtonsManager? _globalPluginButtonsManager;

  void initPluginManager() {
    for(var plugin in _plugins) {
      var _pluginProxy = PluginProxyImpl(this);
      plugin.initPlugin(_pluginProxy);
      _pluginProxy.init(plugin);
    }

    for(var plugin in _plugins) {
      plugin.start();
    }
    _setupGlobalPluginButtonsManager();
  }

  /// Register plugin
  /// 1. Add plugin toolbar
  /// 2. Add plugin settings
  void registerEditorPlugin(PluginProxyImpl proxy, EditorPluginRegisterInformation pluginInfo) {
    if(_editorPluginInstances.containsKey(proxy)) return; // Duplicated

    _editorPluginInstances[proxy] = pluginInfo;
    _editorToolbarInfo.add(pluginInfo.toolbarInformation);
    for(var setting in pluginInfo.settingsInformation) {
      _addToSupportedSetting(pluginInfo.pluginName, setting);
    }
    if(pluginInfo.onBlockChanged != null) {
      registerBlockContentChangeEventListener(pluginInfo.onBlockChanged!);
    }
  }
  void registerGlobalPlugin(PluginProxyImpl proxy, GlobalPluginRegisterInformation pluginInfo) {
    if(_globalPluginInstances.containsKey(proxy)) return; // Duplicated

    _globalPluginInstances[proxy] = pluginInfo;
    _globalToolbarInfo.add(pluginInfo.toolbarInformation);
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
      type: _convertSettingType(setting.type),
    );
    _pluginSupportedSettings.add(settingData);
  }
  SettingType _convertSettingType(PluginSettingType type) {
    switch(type) {
      case PluginSettingType.string:
        return SettingType.string;
      case PluginSettingType.number:
        return SettingType.number;
      case PluginSettingType.bool:
        return SettingType.bool;
      default:
        return SettingType.string;
    }
  }
  void _setupGlobalPluginButtonsManager() {
    final tools = _globalToolbarInfo.toList();
    _globalPluginButtonsManager = GlobalPluginButtonsManager(
      key: _globalPluginButtonsManagerKey,
      tools: tools,
    );
  }

  List<Widget> buildButtons({
    required AppearanceSetting appearance,
    required Controller controller,
  }) {
    var result = <Widget>[];
    for(var item in _editorToolbarInfo) {
      var button = ToolbarButton(
        icon: Icon(item.buttonIcon, size: appearance.iconSize),
        appearance: appearance,
        tip: item.tip,
        controller: controller,
        onPressed: item.action,
      );
      result.add(button);
    }
    return result;
  }
  Widget? buildGlobalButtons({
    required Controller controller,
  }) {
    return _globalPluginButtonsManager;
  }

  String getSelectedOrFocusedContent() {
    var content = controller.selectionController.getSelectedContent();
    if(content.isEmpty) {
      content = controller.getEditingBlockState()?.getPlainText()?? '';
    }
    return content;
  }
  String? getSettingValue(PluginProxyImpl proxy, String pluginKey) {
    final pluginName = _editorPluginInstances[proxy]?.pluginName?? _globalPluginInstances[proxy]?.pluginName;
    if(pluginName == null) return null; // Check

    String key = '${Constants.settingKeyPluginPrefix}/$pluginName/$pluginKey';
    return controller.setting.getSetting(key);
  }
  void sendTextToClipboard(String text) {
    //TODO should add toast notification while finished
    EditorController.copyTextToClipboard(text);
  }
  String? appendTextToNextBlock(String blockId, String text) {
    var blockState = controller.getBlockState(blockId);
    if(blockState == null) return null;

    text = text.replaceAll('\r', '');
    var splitTexts = text.split('\n');
    var blockIds = blockState.appendBlocksWithTexts(splitTexts);
    CallbackRegistry.refreshDoc();
    return blockIds.isEmpty? null: blockIds[blockIds.length - 1];
  }

  String? getEditingBlockId() {
    return controller.getEditingBlockId();
  }

  void closeDialog() {
    CallbackRegistry.getFloatingViewManager()?.clearPluginDialog();
  }
  void showDialog(String title, Widget subChild) {
    closeDialog();
    final widget = _createDialog(title, subChild, closeDialog);
    CallbackRegistry.getFloatingViewManager()?.showPluginDialog(widget);
  }

  void closeGlobalDialog() {
    _globalPluginButtonsManagerKey.currentState?.hideButtons();
  }
  void showGlobalDialog(String title, Widget widget) {
    _globalPluginButtonsManagerKey.currentState?.hideButtons();
  }

  void showToast(String message) {
    CallbackRegistry.showToast(message);
  }

  List<SettingData> getPluginSupportedSettings() {
    return _pluginSupportedSettings;
  }

  void addExtra(PluginProxyImpl proxy, String blockId, String content) {
    var pluginInfo = _editorPluginInstances[proxy];
    if(pluginInfo == null) return;
    var blockState = controller.getBlockState(blockId);
    //TODO should check if document is still opening here
    if(blockState == null) return;
    final pluginName = pluginInfo.pluginName;
    final key = 'plugin/$pluginName';
    blockState.addExtra(key, content);
  }
  void clearExtra(PluginProxyImpl proxy, String blockId) {
    var pluginInfo = _editorPluginInstances[proxy];
    if(pluginInfo == null) return;
    var blockState = controller.getBlockState(blockId);
    //TODO should check if document is still opening here
    if(blockState == null) return;
    final pluginName = pluginInfo.pluginName;
    final key = 'plugin/$pluginName';
    blockState.clearExtra(key);
  }
  UserNotes? getUserNotes() {
    // Check privilege
    final allowSendingNotesToPlugins = controller.setting.getSetting(Constants.settingKeyAllowSendingNotesToPlugins);
    if(allowSendingNotesToPlugins == null || allowSendingNotesToPlugins != 'true') return null;

    final docManager = controller.docManager;
    final documents = docManager.getAllDocuments();
    List<UserNote> notes = [];
    for(var document in documents) {
      final docId = document.docId;
      final title = document.title;
      final doc = docManager.getDocument(docId);
      if(doc == null) continue;
      final paras = doc.paragraphs;
      List<NoteContent> blocks = [];
      for(var para in paras.sublist(1)) { // Skip the title
        final blockId = para.getBlockId();
        final blockContent = para.getPlainText();
        final userBlock = NoteContent(blockId: blockId, content: blockContent);
        blocks.add(userBlock);
      }
      final userNote = UserNote(noteId: docId, title: title, contents: blocks);
      notes.add(userNote);
    }
    return UserNotes(notes: notes);
  }

  bool createNote(String title, String content) {
    final docManager = controller.docManager;
    final result = docManager.createDocument(title, content);
    controller.refreshDocNavigator();
    return result;
  }

  Platform getPlatform() {
    return PlatformImpl(
      environment: controller.environment,
    );
  }

  List<void Function(BlockChangedEventData)> blockContentChangedEventHandlerQueue = [];
  void registerBlockContentChangeEventListener(void Function(BlockChangedEventData) handler) {
    var queue = blockContentChangedEventHandlerQueue;
    if(queue.contains(handler)) return;
    queue.add(handler);
  }
  void produceBlockContentChangedEvent(String blockId, String content) {
    var queue = blockContentChangedEventHandlerQueue;
    final data = BlockChangedEventData(blockId: blockId, content: content);
    for(var callback in queue) {
      callback.call(data);
    }
  }

  Widget _buildTitleBar(String title, void Function() closeCallback) {
    if(title.isEmpty) {
      return Container();
    }
    var titleText = Text(title);
    var button = CupertinoButton(
      child: const Icon(Icons.close),
      onPressed: closeCallback,
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
  Widget _createDialog(String title, Widget subChild, void Function() closeCallback) {
    CallbackRegistry.hideKeyboard();
    final widget = LayoutBuilder(
      builder: (context, constraints) {
        final isSmallView = controller.environment.isSmallView(context);
        double width = 300;
        double height = 300;
        if(isSmallView) {
          width = double.infinity;
          height = double.infinity;
        }
        var child = Container(
          child: subChild,
        );
        var titleBar = _buildTitleBar(title, closeCallback);
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
        // double verticalPadding = controller.getToolbarHeight()?? 16.0;
        var container = Container(
          margin: const EdgeInsets.fromLTRB(5, 128, 5, 5),
          alignment: Alignment.bottomRight,
          child: Material(
            elevation: 8.0,
            borderRadius: BorderRadius.circular(8.0),
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
    return widget;
  }
}

class PluginProxyImpl implements PluginProxy {
  final PluginManager _manager;
  late final PluginInstance _instance;

  PluginProxyImpl(PluginManager pluginManager): _manager = pluginManager;
  PluginInstance getInstance() => _instance;

  void init(PluginInstance instance) => _instance = instance;

  @override
  void registerEditorPlugin(EditorPluginRegisterInformation pluginRegisterInfo) {
    _manager.registerEditorPlugin(this, pluginRegisterInfo);
  }

  @override
  void registerGlobalPlugin(GlobalPluginRegisterInformation pluginRegisterInfo) {
    _manager.registerGlobalPlugin(this, pluginRegisterInfo);
  }

  @override
  void showDialog(String title, Widget child) {
    _manager.showDialog(title, child);
  }
  @override
  void closeDialog() {
    _manager.closeDialog();
  }

  @override
  void showToast(String message) {
    _manager.showToast(message);
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

  @override
  void addExtra(String blockId, String content) {
    _manager.addExtra(this, blockId, content);
  }

  @override
  void clearExtra(String blockId) {
    _manager.clearExtra(this, blockId);
  }

  @override
  UserNotes? getUserNotes() {
    return _manager.getUserNotes();
  }

  @override
  bool createNote(String title, String content) {
    return _manager.createNote(title, content);
  }

  @override
  Platform getPlatform() {
    return _manager.getPlatform();
  }
}

class PlatformImpl implements Platform {
  final Environment _environment;
  PlatformImpl({
    required Environment environment,
  }): _environment = environment;

  @override
  bool isWindows() {
    return _environment.isWindows();
  }

  @override
  bool isMacOS() {
    return _environment.isMac();
  }

  @override
  bool isAndroid() {
    return _environment.isAndroid();
  }

  @override
  bool isIOS() {
    return _environment.isIos();
  }

  @override
  bool isMobile() {
    return _environment.isMobile();
  }
}
