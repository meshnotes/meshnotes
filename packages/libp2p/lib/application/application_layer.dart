import 'dart:async';
import 'dart:convert';
import 'village_data.dart';
import 'package:libp2p/dal/village_db.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/overlay_controller.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:my_log/my_log.dart';

import 'application_api.dart';

enum VillageMode {
  loneWolf,
}

class Village implements ApplicationController {
  static const logPrefix = '[Village]';
  static const _appName = 'village';
  VillageOverlay _overlay;
  VillageMode _mode;
  int localPort;
  String upperAppName;
  VillageMessageHandler messageHandler;
  VillageDbHelper _db;

  // Villager properties
  String _userId;

  Village({
    required String userId,
    required List<String> sponsors,
    this.localPort = 0,
    required this.messageHandler,
    VillageMode mode = VillageMode.loneWolf,
    required VillageOverlay overlay,
    required VillageDbHelper db,
    required this.upperAppName,
  }): _mode = mode, _userId = userId, _overlay = overlay, _db = db {
    MyLogger.info('${logPrefix} register app=$_appName');
    _overlay.registerApplication(_appName, this, setDefault: true);
    _overlay.registerApplication(upperAppName, this);
  }

  Future<void> start() async {
    await _overlay.start();
    Timer.periodic(Duration(milliseconds: 5000), _timerHandler);
  }

  @override
  void onData(VillagerNode node, String appName, String type, String data) {
    MyLogger.info('${logPrefix}: Receive village data($data) of type($type) to application($appName)');
    switch(type) {
      case ProvideAppType:
        if(upperAppName == appName) {
          messageHandler.handleProvide?.call(data);
        } else {
          _onDefaultProvide(data);
        }
        break;
      case QueryAppType:
        if(upperAppName == appName) {
          messageHandler.handleQuery?.call(data);
        } else {
          _onDefaultQuery(data);
        }
      default:
        MyLogger.info('onData: receive unrecognized app type: $type, data=$data');
        break;
    }
  }

  void sendVersionTree(String resourceJson) {
    MyLogger.info('efantest: Preparing to send resource: $resourceJson');
    //TODO Optimize the code below to only send message to selected nodes
    _overlay.sendToAllNodesOfUser(upperAppName, this, _userId, ProvideAppType, resourceJson);
  }

  void sendRequireVersions(String requiredVersions) {
    MyLogger.info('efantest: Preparing to send require_versions: $requiredVersions');
    _overlay.sendToAllNodesOfUser(upperAppName, this, _userId, QueryAppType, requiredVersions);
  }

  void sendVersions(String sendVersions) {
    MyLogger.info('efantest: Preparing to send send_versions: $sendVersions');
    _overlay.sendToAllNodesOfUser(upperAppName, this, _userId, ProvideAppType, sendVersions);
  }

  void sendProvide(String userKey, List<String> resources) {
    ProvideMessage msg = ProvideMessage(userPubKey: userKey, resources: resources);
    _overlay.sendToAllNodesOfUser(upperAppName, this, _userId, ProvideAppType, jsonEncode(msg));
  }

  void _timerHandler(Timer _t) {
    if(_mode == VillageMode.loneWolf) {
      // In lone wolf mode, only sync data to warehouses with the same user_id
      _contactVillagers();
      _syncData();
    }
  }

  void _contactVillagers() {
    //TODO Try hard to keep at least 1 villager is contacted
  }
  void _syncData() {
    var data = _findUpdatedData();
    if(data != null) {
      var nodes = _findWarehousesByUserId(_userId);
      _syncDataToWarehouse(nodes, data);
    }
  }
  List<int>? _findUpdatedData() {
    // TODO Find updated data
    return null;
  }
  List<String> _findWarehousesByUserId(String _id) {
    // TODO Find node ids by user id
    return [];
  }
  void _syncDataToWarehouse(List<String> nodeIds, List<int> data) {
    // TODO Sync data to warehouses indicated by nodeIds
  }

  /// Not implemented yet
  void _onDefaultProvide(String data) {
  }
  /// Not implemented yet
  void _onDefaultQuery(String data) {
  }
}