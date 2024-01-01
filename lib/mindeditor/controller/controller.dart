import 'dart:io';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/environment.dart';
import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/mindeditor/document/document_manager.dart';
import 'package:mesh_note/net/net_controller.dart';
import 'package:mesh_note/mindeditor/view/mind_edit_block.dart';
import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../document/dal/fake_db_helper.dart';
import '../document/paragraph_desc.dart';
import '../setting/setting.dart';
import 'device.dart';
import 'gesture_handler.dart';
import 'package:platform_device_id_v3/platform_device_id.dart';


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
  String deviceId = '';
  String simpleDeviceId = '';
  String userKey = '166f826179b0b077c90efe9bda61506844e658bba43f7edc67f741c1ccfccdfe';

  // Getters
  DocumentManager get docManager => _docManager!;
  Document? get document => docManager.getCurrentDoc();

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

    // Will failed in flutter test mode, so disabled it
    if(!test) {
      await _genDeviceId();
      MyLogger.info('initAll: device_id=$deviceId, simple_device_id=$simpleDeviceId');
    }

    await dbHelper.init();
    _docManager = DocumentManager(db: dbHelper);

    // Load settings before starting network
    MyLogger.debug('initAll: load settings');
    setting.loadFromDb(dbHelper);

    MyLogger.debug('initAll: start network');
    network = _net;
    network.start(setting, deviceId, userKey);

    MyLogger.debug('initAll: finish initialization');
    return true;
  }

  Future<void> _genDeviceId() async {
    deviceId = (await PlatformDeviceId.getDeviceId??'').trim();

    // simpleDeviceId is composed of first 8 character of deviceId and first 8 character of SHA256 of deviceId
    var len = deviceId.length > 8? 8: deviceId.length;
    simpleDeviceId = deviceId.substring(0, len);
    final shaOfId = HashUtil.hashText(deviceId);
    len = shaOfId.length > 8? 8: shaOfId.length;
    simpleDeviceId += shaOfId.substring(0, len);
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
    CallbackRegistry.triggerSelectionChangedEvent(selection);
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
    var versionData = docManager.genAndSaveNewVersionTree();
    if(versionData.isEmpty) {
      return false;
    }
    MyLogger.info('syncVersionTree: $versionData');
    network.sendNewVersionTree(versionData);
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
  void receiveVersions(List<SendVersionsNode> versions) {
    MyLogger.info('efantest: receive versions message: $versions');
    docManager.assembleVersions(versions);
  }
}
