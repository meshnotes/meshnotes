import 'dart:async';
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
  OnDataType? handleData;

  // Villager properties
  String _userId;

  Village({
    required String userId,
    required List<String> sponsors,
    this.localPort = 0,
    this.handleData,
    VillageMode mode = VillageMode.loneWolf,
    required VillageOverlay overlay,
  }): _mode = mode, _userId = userId, _overlay = overlay {
    MyLogger.info('${logPrefix} register app=$_appName');
    _overlay.registerApplication(_appName, this);
  }

  Future<void> start() async {
    await _overlay.start();
    Timer.periodic(Duration(milliseconds: 5000), _timerHandler);
  }

  @override
  void onData(VillagerNode node, String app, String type, String data) {
    MyLogger.info('efantest: receive village data: $data of type($type)');
    handleData?.call(type, data);
  }

  void sendVersionTree(String versionTree) {
    MyLogger.info('efantest: Preparing to send version tree: $versionTree');
    _overlay.sendToAllNodesOfUser(this, _userId, VersionTreeAppType, versionTree);
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
}