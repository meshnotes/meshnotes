import 'dart:convert';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/overlay/overlay_controller.dart';
import 'package:libp2p/dal/village_db.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:libp2p/utils.dart';
import 'package:my_log/my_log.dart';
import 'package:server/server_db.dart';

class RelayApplication implements ApplicationController {
  static const logPrefix = '[RelayApplication]';
  final VillageOverlay _overlay;
  final VillageDbHelper _db;
  final ServerDbHelper _serverDb;
  final String upperAppName;
  final Map<String, AppMessageType> _mapOfAppMessageType = {};

  RelayApplication({
    required VillageOverlay overlay,
    required VillageDbHelper db,
    required ServerDbHelper serverDb,
    required this.upperAppName,
  })  : _overlay = overlay,
        _db = db,
        _serverDb = serverDb {
    MyLogger.info('$logPrefix register app=relay_village');
    _overlay.registerApplication('relay_village', this, setDefault: true);
    _overlay.registerApplication(upperAppName, this);
    for (var e in AppMessageType.values) {
      _mapOfAppMessageType[e.value] = e;
    }
  }

  @override
  void onData(VillagerNode node, String appName, String type, String data) {
    TimeCostStatistics stats = TimeCostStatistics(startTime: networkNow());
    MyLogger.debug('$logPrefix: Receive village data of type($type) to application($appName): ${data.length > 100 ? data.substring(0, 100) : data}');
    
    var appType = _mapOfAppMessageType[type];
    if (appType == null) {
      MyLogger.warn('$logPrefix onData: receive unrecognized app type: $type, data=$data');
      return;
    }

    switch (appType) {
      case AppMessageType.provideAppType:
        MyLogger.info('$logPrefix Received provideAppType data. Storing/Handling...');
        try {
          final decoded = jsonDecode(data);
          final signedResources = SignedResources.fromJson(decoded);
          final userPublicKey = signedResources.userPublicId;
          
          for (var resource in signedResources.resources) {
            if (resource.key == 'version_tree') {
              MyLogger.info('$logPrefix Found version_tree DAG. Saving to DB for user $userPublicKey');
              _serverDb.saveVersionTree(
                userPublicKey,
                node.nodeId,
                DateTime.now().millisecondsSinceEpoch,
                resource.data,
              );
            }
          }
        } catch (e) {
          MyLogger.warn('$logPrefix Failed to parse provideAppType data: $e');
        }
        break;
      case AppMessageType.queryAppType:
        MyLogger.info('$logPrefix Received queryAppType data.');
        break;
      case AppMessageType.publishAppType:
        MyLogger.info('$logPrefix Received publishAppType data. Storing/Handling...');
        break;
    }
  }

  Future<void> start() async {
    await _overlay.start();
    MyLogger.info('$logPrefix Started relay application overlay.');
  }
}
