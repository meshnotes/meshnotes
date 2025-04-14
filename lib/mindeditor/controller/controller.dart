import 'dart:convert';
import 'dart:io';
import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/environment.dart';
import 'package:mesh_note/mindeditor/document/collaborate/merge_task.dart';
import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/mindeditor/document/document_manager.dart';
import 'package:mesh_note/mindeditor/controller/selection_controller.dart';
import 'package:mesh_note/net/net_controller.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/tasks/event_tasks.dart';
import 'package:mesh_note/tasks/ui_event_manager.dart';
import 'package:my_log/my_log.dart';
import '../../net/init.dart';
import '../../net/version_chain_api.dart';
import '../../plugin/plugin_manager.dart';
import '../../util/idgen.dart';
import '../document/paragraph_desc.dart';
import '../setting/constants.dart';
import '../setting/setting.dart';
import 'device.dart';
import 'editor_controller.dart';
import 'gesture_handler.dart';


enum ControllerState {
  initializing,
  loggingIn,
  running,
}
class Controller {
  bool isUnitTest = false;
  bool isDebugMode = false;
  DocumentManager? _docManager;
  MergeTask? _mergeTaskRunner;
  late DbHelper dbHelper;
  final FocusNode globalFocusNode = FocusNode();
  final Environment environment = Environment();
  final Device device = Device();
  late final Setting setting; // = Setting.defaultSetting;
  // Mouse and gesture handler
  late final GestureHandler gestureHandler;
  late final NetworkController network;
  String deviceId = 'Unknown';
  late final SelectionController selectionController;
  String simpleDeviceId = '';
  UserPrivateInfo? userPrivateInfo;
  late final PluginManager _pluginManager;
  final EvenTasksManager eventTasksManager = EvenTasksManager();
  final UIEventManager uiEventManager = UIEventManager();
  double? _toolbarHeight;
  ControllerState _state = ControllerState.initializing;
  String? _logPath; // Need send to net_controller, so saved it

  // Getters
  DocumentManager get docManager => _docManager!;
  Document? get document => docManager.getCurrentDoc();

  PluginManager get pluginManager => _pluginManager;

  double? getToolbarHeight() => _toolbarHeight;
  void setToolbarHeight(double height) {
    _toolbarHeight = height;
  }

  // Use singleton pattern to ensure Controller is not recreated
  static final Controller _theOne = Controller._internal();
  Controller._internal();
  factory Controller() {
    return _theOne;
  }

  Future<bool> initAll() async {
    const isProduct = bool.fromEnvironment('dart.vm.product');
    if(isProduct) {
      _logPath = await environment.getLogPath();
      MyLogger.resetOutputToFile(path: _logPath!);
    }
    dbHelper = DbHelper();
    gestureHandler = GestureHandler(controller: _theOne);
    device.init();
    // Load settings before starting network
    final confFile = await environment.getExistFileFromLibraryPathsByEnvironment('setting.conf');
    MyLogger.info('initAll: load settings from $confFile');
    setting = Setting(confFile);
    setting.load();

    MyLogger.debug('initAll: init db');
    await dbHelper.init();
    _docManager = DocumentManager(db: dbHelper);
    _mergeTaskRunner = MergeTask(db: dbHelper);

    // Load user information from setting
    userPrivateInfo = _loadUserInfo(setting);
    MyLogger.info('initAll: load user(${userPrivateInfo?.userName}) from setting');

    // Will failed in flutter test mode, so disabled it
    await _genDeviceId();
    MyLogger.info('initAll: device_id=$deviceId, simple_device_id=$simpleDeviceId');

    network = await initNet();
    if(!tryStartingNetwork()) {
      MyLogger.info('initAll: try starting network failed');
    }

    selectionController = SelectionController(this);

    _pluginManager = PluginManager();
    _pluginManager.initPluginManager();

    setting.addAdditionalSettings(_pluginManager.getPluginSupportedSettings());
    setting.load();

    _initGlobalEventTasks(); // Register some global event tasks

    MyLogger.info('initAll: finish initialization');
    eventTasksManager.triggerAfterInit();
    return true;
  }

  void setLoggingInState() {
    _state = ControllerState.loggingIn;
  }
  void setRunningState() {
    _state = ControllerState.running;
  }
  bool isRunning() {
    return _state == ControllerState.running;
  }

  void _initGlobalEventTasks() {
    // Hide keyboard when user switch to navigator
    eventTasksManager.addUserSwitchToNavigatorTask(() {
      CallbackRegistry.hideKeyboard();
    });
    // Check if the clipboard data is available every 3 seconds
    eventTasksManager.addTimerTask('checkClipboard', () {
      EditorController.checkIfReadyToPaste();
    }, 3000);
  }

  /// Network could be starting only when the user information is ready
  /// And user private key should not be 'guest'
  bool tryStartingNetwork() {
    if(userPrivateInfo == null) return false;
    if(userPrivateInfo!.privateKey == Constants.userNameAndKeyOfGuest) return false;

    network.start(
      setting,
      deviceId,
      userPrivateInfo!,
      _logPath,
    );
    MyLogger.info('Network layer started');
    return true;
  }

  Future<void> _genDeviceId() async {
    // deviceId = (await PlatformDeviceId.getDeviceId??'').trim();
    var platformDeviceId = await _getDeviceIdByPlatform();
    if(platformDeviceId != null) {
      deviceId = platformDeviceId;
    } else {
      final userKey = userPrivateInfo?.privateKey;
      deviceId = HashUtil.hashText(userKey?? IdGen.getUid()) + ':Unknown';
    }

    // simpleDeviceId is composed of first 8 character of deviceId and first 8 character of SHA256 of deviceId
    var len = deviceId.length > 8? 8: deviceId.length;
    simpleDeviceId = deviceId.substring(0, len);
    final shaOfId = HashUtil.hashText(deviceId);
    len = shaOfId.length > 8? 8: shaOfId.length;
    simpleDeviceId += shaOfId.substring(0, len);
  }
  Future<String?> _getDeviceIdByPlatform() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    if(environment.isAndroid()) {
      var plugin = const AndroidId();
      var id = await plugin.getId();
      return id;
    }
    if(environment.isIos()) {
      var data = await deviceInfoPlugin.iosInfo;
      return data.identifierForVendor;
    }
    if(environment.isMac()) {
      var macInfo = await deviceInfoPlugin.macOsInfo;
      return macInfo.systemGUID;
    }
    if(environment.isLinux()) {
      var linuxInfo = await deviceInfoPlugin.linuxInfo;
      return linuxInfo.machineId;
    }
    if(environment.isWindows()) {
      var winInfo = await deviceInfoPlugin.windowsInfo;
      return winInfo.deviceId;
    }
    return null;
  }
  UserPrivateInfo? _loadUserInfo(Setting _setting) {
    final userInfo = _setting.getSetting(Constants.settingKeyUserInfo);
    if(userInfo == null) return null;

    try {
      return UserPrivateInfo.fromBase64(userInfo);
    } catch(e) {
      MyLogger.warn('Error loading user info from setting: $e');
      return null;
    }
  }

  MouseCursor getHandCursor() {
    if(Platform.isWindows) {
      return SystemMouseCursors.click;
    }
    return SystemMouseCursors.grab;
  }

  void setBlockStateToTreeNode(String id, MindEditBlockState _state) {
    document?.setBlockStateToTreeNode(id, _state);
  }
  ParagraphDesc? getBlockDesc(String id) {
    if(document == null) {
      return null;
    }
    return document!.getParagraph(id);
    // return _docTree[id];
  }

  void clearEditingBlock() {
    document?.clearEditingBlock();
  }
  void setEditingBlockId(String _id) {
    document?.setEditingBlockId(_id);
  }
  String? getEditingBlockId() {
    return document?.getEditingBlockId();
  }

  MindEditBlockState? getBlockState(String _id) {
    return document?.getBlockState(_id);
  }
  MindEditBlockState? getEditingBlockState() {
    return document?.getEditingBlockState();
  }

  // Document
  void _refreshDocumentView() {
    if(document != null) {
      CallbackRegistry.resetTitleBar(document!.getTitlePath());
      CallbackRegistry.openDocument(document!);
    } else {
      CallbackRegistry.clearTitleBar();
      CallbackRegistry.closeDocument();
    }
  }
  void openDocument(String docId) {
    _docManager!.openDocument(docId);
    _refreshDocumentView();
  }
  void newDocument() {
    var docId = _docManager!.newDocument();
    // var doc = _docManager!.getCurrentDoc();
    // _currentEditorState!.refresh();
    refreshDocNavigator();
    openDocument(docId);
  }
  void closeDocument() {
    _docManager!.closeDocument();
    _refreshDocumentView();
  }
  void deleteDocument() {
    _docManager!.deleteCurrentDocument();
    closeDocument();
    refreshDocNavigator();
    tryToSaveAndSendVersionTree();
  }

  void refreshDocNavigator() {
    CallbackRegistry.triggerDocumentChangedEvent();
  }

  void triggerSelectionChanged(TextSpansStyle? selection) {
    CallbackRegistry.triggerSelectionStyleEvent(selection);
  }
  void triggerBlockFormatChanged(ParagraphDesc? para) {
    var type = para?.getBlockType();
    var listing = para?.getBlockListing();
    var level = para?.getBlockLevel();
    CallbackRegistry.triggerEditingBlockFormatEvent(type, listing, level);
  }

  /// Send current newest version if:
  /// 1. There is network peer(s)
  /// 2. Currently not modified or syncing
  /// 3. the newest version is valid(not '')
  void sendVersionBroadcast() {
    if(network.isAlone()) return;
    if(docManager.hasModified() || docManager.isBusy()) return;
    var latestVersion = docManager.getLatestVersion();
    MyLogger.info('sendVersionBroadcast: latestVersion=$latestVersion');
    if(latestVersion.isEmpty) return;

    network.sendVersionBroadcast(latestVersion);
  }
  bool tryToSaveAndSendVersionTree() {
    // If there is no modification, or is currently syncing, don't generate new version tree
    if(!docManager.hasModified() || docManager.isBusy()) return false;

    // If there is no network peer, try to generate a new version tree and override current version
    // The purpose is to reduce the version tree size
    final isAlone = network.isAlone();
    if(isAlone) {
      docManager.tryToGenNewVersionTreeAndOverrideCurrent();
      return true;
    } else {
      docManager.genNewVersionTree();
      return _sendCurrentVersionTree();
    }
  }
  void clearHistoryVersions() {
    docManager.clearHistoryVersions();
  }
  bool _sendCurrentVersionTree() {
    var (versionData, timestamp) = docManager.genCurrentVersionTree();
    if(versionData.isEmpty || timestamp == 0) {
      return false;
    }
    MyLogger.info('sendVersionTree: $versionData');
    network.sendNewVersionTree(versionData, timestamp);
    docManager.markCurrentVersionAsSyncing();
    return true;
  }
  void sendRequireVersions(List<String> missingVersions) {
    network.sendRequireVersions(missingVersions);
  }
  void sendRequireVersionTree(String latestVersion) {
    //TODO Currently ignore latestVersion, but later should support specified version
    network.sendRequireVersionTree(Constants.resourceKeyVersionTree);
  }

  void receiveVersionBroadcast(String latestVersion) {
    /// 1. Check if already have latestVersion
    /// 2. If not, send require version tree
    /// 3. If there is the version, but no object, send require version
    MyLogger.info('receive version broadcast, latestVersion=$latestVersion');
    // if(docManager.isBusy()) {
    //   MyLogger.info('receiveVersionBroadcast: too busy to handle version broadcast: $latestVersion');
    //   //TODO should add a task queue to delay assembling version tree, instead of simply drop the tree
    //   return;
    // }
    final version = dbHelper.getVersionData(latestVersion);
    if(version == null) {
      MyLogger.info('receiveVersionBroadcast: need entire version tree for tree node $latestVersion');
      // Send require version tree
      sendRequireVersionTree(latestVersion);
      return;
    }
    if(!dbHelper.hasObject(latestVersion)) {
      MyLogger.info('receiveVersionBroadcast: need version objects for tree node $latestVersion');
      sendRequireVersions([latestVersion]);
    }
  }
  void receiveVersionTree(List<VersionNode> dag) {
    _mergeTaskRunner?.addVersionTree(dag);
    // if(docManager.isBusy()) {
    //   MyLogger.info('receiveVersionTree: too busy to handle version tree: $dag');
    //   //TODO should add a task queue to delay assembling version tree, instead of simply drop the tree
    //   return;
    // }
    // MyLogger.info('receiveVersionTree: receive version tree: $dag');
    // docManager.assembleVersionTree(dag);
  }
  void mergeVersionTree() {
    if(docManager.isBusy()) {
      MyLogger.info('mergeVersionTree: too busy to merging');
      return;
    }
    docManager.mergeVersionTree();
  }
  void receiveRequireVersions(List<String> requiredVersions) {
    MyLogger.info('receiveRequireVersions: receive require versions message: $requiredVersions');
    for(final item in requiredVersions) {
      //TODO Currently only send version tree if there is any resource with the key 'version_tree'.
      //TODO Maybe should make ordinary resources and version_tree coexist
      if(item == Constants.resourceKeyVersionTree) {
        _sendCurrentVersionTree();
        return;
      }
    }
    //TODO should make the log shorter
    var versions = docManager.assembleRequireVersions(requiredVersions);
    MyLogger.info('receiveRequireVersions: preparing to send versions: $versions');
    network.sendVersions(versions);
  }
  void receiveResources(List<UnsignedResource> resources) {
    MyLogger.info('receiveResources: receive resources: $resources');
    List<VersionChain> versionChains = [];
    List<UnsignedResource> nonChainResources = [];
    for(var res in resources) {
      final key = res.key;
      // Gather version_tree resources together and solve it in the end.
      // This scenario is caused by receiving version broadcast, and then require entire version tree
      if(key == Constants.resourceKeyVersionTree) {
        var versionChain = VersionChain.fromJson(jsonDecode(res.data));
        versionChains.add(versionChain);
      } else {
        nonChainResources.add(res);
      }
    }
    if(nonChainResources.isNotEmpty) {
      _mergeTaskRunner?.addResources(nonChainResources);
      // docManager.assembleResources(nonChainResources);
    }

    for(var chain in versionChains) {
      receiveVersionTree(chain.versionDag);
    }
  }
}
