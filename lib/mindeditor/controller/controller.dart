import 'dart:convert';
import 'dart:io';
import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/environment.dart';
import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/mindeditor/document/document_manager.dart';
import 'package:mesh_note/mindeditor/controller/selection_controller.dart';
import 'package:mesh_note/net/net_controller.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../../net/version_chain_api.dart';
import '../../plugin/plugin_manager.dart';
import '../../util/idgen.dart';
import '../document/dal/fake_db_helper.dart';
import '../document/paragraph_desc.dart';
import '../setting/constants.dart';
import '../setting/setting.dart';
import 'device.dart';
import 'gesture_handler.dart';

class Controller {
  bool isUnitTest = false;
  bool isDebugMode = false;
  DocumentManager? _docManager;
  late DbHelper dbHelper;
  final FocusNode globalFocusNode = FocusNode();
  final Environment environment = Environment();
  final Device device = Device();
  final Setting setting = Setting.defaultSetting;
  // Mouse and gesture handler
  late final GestureHandler gestureHandler;
  late final NetworkController network;
  String deviceId = 'Unknown';
  late final SelectionController selectionController;
  String simpleDeviceId = '';
  UserPrivateInfo? userPrivateInfo;
  late final PluginManager _pluginManager;
  double? _toolbarHeight;

  // Getters
  DocumentManager get docManager => _docManager!;
  Document? get document => docManager.getCurrentDoc();

  PluginManager get pluginManager => _pluginManager;

  double? getToolbarHeight() => _toolbarHeight;
  void setToolbarHeight(double height) {
    _toolbarHeight = height;
  }

  // 为了避免Controller在各种Widget被重新创建，使用全局唯一实例
  static final Controller _theOne = Controller();
  static Controller get instance => _theOne;

  static void init({bool test=false}) {
    if(test) {
      _theOne.isUnitTest = true;
      _theOne.dbHelper = FakeDbHelper();
    } else {
      _theOne.dbHelper = RealDbHelper();
    }
    _theOne.gestureHandler = GestureHandler(controller: _theOne);
    _theOne.device.init();
  }

  Future<bool> initAll(NetworkController _net, {bool test=false}) async {
    MyLogger.debug('initAll: init db');

    await dbHelper.init();
    _docManager = DocumentManager(db: dbHelper);

    // Load settings before starting network
    MyLogger.debug('initAll: load settings');
    setting.loadFromDb(dbHelper);

    // Load user information from setting
    userPrivateInfo = _loadUserInfo(setting);
    MyLogger.info('initAll: load user(${userPrivateInfo?.userName}) from setting');

    // Will failed in flutter test mode, so disabled it
    if(!test) {
      await _genDeviceId();
      MyLogger.info('initAll: device_id=$deviceId, simple_device_id=$simpleDeviceId');
    }

    network = _net;
    if(!tryStartingNetwork()) {
      MyLogger.info('initAll: try starting network failed');
    }

    selectionController = SelectionController();

    _pluginManager = PluginManager();
    _pluginManager.initPluginManager();

    MyLogger.debug('initAll: finish initialization');
    return true;
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

  TextEditingValue getCurrentTextEditingValue() {
    var currentState = getEditingBlockState();
    if(currentState == null) {
      MyLogger.warn('Current Block is null, something is wrong!!!');
      return const TextEditingValue(
        text: '',
      );
    }
    return currentState.getCurrentTextEditingValue();
  }

  // Document
  void _refreshDocumentView() {
    CallbackRegistry.resetTitleBar(document!.getTitlePath());
    CallbackRegistry.openDocument(document!);
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

  void refreshDocNavigator() {
    CallbackRegistry.triggerDocumentChangedEvent();
  }

  void triggerSelectionChanged(TextSpansStyle? selection) {
    CallbackRegistry.triggerSelectionStyleEvent(selection);
  }
  void triggerBlockFormatChanged(ParagraphDesc? para) {
    var type = para?.getType();
    var listing = para?.getListing();
    var level = para?.getLevel();
    CallbackRegistry.triggerEditingBlockFormatEvent(type, listing, level);
  }

  bool sendVersionTree() {
    // If there is any modification, generate a new version tree, and try to sync this version
    if(!docManager.hasModified() || docManager.isSyncing()) return false;
    var (versionData, timestamp) = docManager.genAndSaveNewVersionTree();
    if(versionData.isEmpty) {
      return false;
    }
    MyLogger.info('syncVersionTree: $versionData');
    network.sendNewVersionTree(versionData, timestamp);
    return true;
  }

  void sendRequireVersions(List<String> missingVersions) {
    network.sendRequireVersions(missingVersions);
  }

  void receiveVersionTree(List<VersionNode> dag) {
    if(docManager.isSyncing()) {
      MyLogger.info('receiveVersionTree: too busy to handle version tree: $dag');
      //TODO should add a task queue to delay assembling version tree, instead of simply drop the tree
      return;
    }
    MyLogger.info('efantest: receive version tree: $dag');
    docManager.assembleVersionTree(dag);
  }
  void receiveRequireVersions(List<String> requiredVersions) {
    MyLogger.info('efantest: receive require versions message: $requiredVersions');
    var versions = docManager.assembleRequireVersions(requiredVersions);
    MyLogger.info('efantest: preparing to send versions: $versions');
    network.sendVersions(versions);
  }
  void receiveResources(List<UnsignedResource> resources) {
    List<VersionChain> versionChains = [];
    List<UnsignedResource> nonChainResources = [];
    for(var res in resources) {
      final key = res.key;
      // Gather version_tree resources together and solve it in the end
      if(key == Constants.resourceKeyVersionTree) {
        var versionChain = VersionChain.fromJson(jsonDecode(res.data));
        versionChains.add(versionChain);
      } else {
        nonChainResources.add(res);
      }
    }
    docManager.assembleResources(nonChainResources);

    for(var chain in versionChains) {
      receiveVersionTree(chain.versionDag);
    }
  }
}
