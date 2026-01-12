import 'dart:async';
import 'package:libp2p/dal/village_db.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/overlay_controller.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:libp2p/utils.dart';
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
  String upperAppName;
  VillageMessageHandler messageHandler;
  VillageDbHelper _db;
  Map<String, AppMessageType> _mapOfAppMessageType = {};
  int _lastPrintStatisticsTimestamp = 0;
  static const _printStatisticsInterval = 10000; // Print statistics every 10 seconds
  _TimeCostStatistics _timeCostStatistics = _TimeCostStatistics();

  // Villager properties
  // String _userId; // It seems this is not necessary

  Village({
    // required String userId,
    required List<String> sponsors,
    required this.messageHandler,
    VillageMode mode = VillageMode.loneWolf,
    required VillageOverlay overlay,
    required VillageDbHelper db,
    required this.upperAppName,
  }): _mode = mode, /*_userId = userId, */_overlay = overlay, _db = db {
    MyLogger.info('${logPrefix} register app=$_appName');
    _overlay.registerApplication(_appName, this, setDefault: true);
    _overlay.registerApplication(upperAppName, this);
    AppMessageType.values.forEach((e) { _mapOfAppMessageType[e.value] = e; });
  }

  Future<void> start() async {
    await _overlay.start();
    Timer.periodic(Duration(milliseconds: 5000), _timerHandler);
  }

  /// Handle the data received from lower layer
  @override
  void onData(VillagerNode node, String appName, String type, String data) {
    TimeCostStatistics stats = TimeCostStatistics(
      startTime: networkNow(),
    );
    MyLogger.debug('${logPrefix}: Receive village data of type($type) to application($appName): ${data.substring(0, 100)}');
    var appType = _mapOfAppMessageType[type];
    if(appType == null) {
      MyLogger.warn('onData: receive unrecognized app type: $type, data=$data');
      return;
    }
    switch(appType) {
      case AppMessageType.provideAppType:
        if(upperAppName == appName) {
          messageHandler.handleProvide?.call(data, stats);
        } else {
          _onDefaultProvide(data);
        }
        break;
      case AppMessageType.queryAppType:
        if(upperAppName == appName) {
          messageHandler.handleQuery?.call(data, stats);
        } else {
          _onDefaultQuery(data);
        }
      case AppMessageType.publishAppType:
        if(upperAppName == appName) {
          messageHandler.handlePublish?.call(data, stats);
        } else {
          _onDefaultPublish(data);
        }
    }
  }

  void newNodeDiscovered(String host, int port, String deviceId) { // Called if using bonjour and discover new nodes
    _overlay.newNodeDiscovered(host, port, deviceId);
  }

  void sendPublish(String msgJson, TimeCostStatistics stats) {
    MyLogger.info('sendPublish: Preparing to send publish: ${msgJson.substring(0, 100)}');
    //TODO Optimize the code below to only send message to selected nodes
    _sendToAllNodesOfUser(AppMessageType.publishAppType, msgJson, stats);
  }
  void sendVersionTree(String resourceJson, TimeCostStatistics stats) {
    MyLogger.info('sendVersionTree: Preparing to send version tree: ${resourceJson.substring(0, 100)}');
    //TODO Optimize the code below to only send message to selected nodes
    _sendToAllNodesOfUser(AppMessageType.provideAppType, resourceJson, stats);
  }
  void sendRequireVersions(String requiredVersions, TimeCostStatistics stats) {
    MyLogger.info('sendRequireVersions: Preparing to send require_versions: ${requiredVersions.substring(0, 100)}');
    //TODO Optimize the code below to only send message to selected nodes
    _sendToAllNodesOfUser(AppMessageType.queryAppType, requiredVersions, stats);
  }
  void sendVersions(String sendVersions, TimeCostStatistics stats) {
    MyLogger.info('sendVersions: Preparing to send versions: ${sendVersions.substring(0, 100)}');
    //TODO Optimize the code below to only send message to selected nodes
    _sendToAllNodesOfUser(AppMessageType.provideAppType, sendVersions, stats);
  }
  void _sendToAllNodesOfUser(AppMessageType type, String data, TimeCostStatistics stats) {
    _overlay.sendToAllNodesOfUser(upperAppName, this, type.value, data);
    stats.finishTime = networkNow();
    _updateTimeCostStatistics(stats);
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
      var nodes = _findWarehousesByUserId();
      _syncDataToWarehouse(nodes, data);
    }
  }
  List<int>? _findUpdatedData() {
    // TODO Find updated data
    return null;
  }
  List<String> _findWarehousesByUserId() {
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
  ///Not implemented yet
  void _onDefaultPublish(String data) {
  }

  void _updateTimeCostStatistics(TimeCostStatistics stats) {
    final applicationCost = stats.transportTime - stats.startTime;
    final isolateCost = stats.receiveTime - stats.transportTime;
    final protocolCost = stats.finishTime - stats.receiveTime;
    _timeCostStatistics.applicationCostMilliseconds += applicationCost;
    _timeCostStatistics.isolateCostMilliseconds += isolateCost;
    _timeCostStatistics.protocolCostMilliseconds += protocolCost;
    final now = networkNow();
    if(now - _lastPrintStatisticsTimestamp >= _printStatisticsInterval) {
      MyLogger.info('[Village Statistics] Time cost statistics: applicationCost=${_timeCostStatistics.applicationCostMilliseconds}ms, isolateCost=${_timeCostStatistics.isolateCostMilliseconds}ms, protocolCost=${_timeCostStatistics.protocolCostMilliseconds}ms');
      _lastPrintStatisticsTimestamp = now;
    }
  }
}

class _TimeCostStatistics {
  int applicationCostMilliseconds = 0;
  int isolateCostMilliseconds = 0;
  int protocolCostMilliseconds = 0;
}