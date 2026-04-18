import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/overlay/overlay_controller.dart';
import 'package:libp2p/dal/village_db.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:libp2p/utils.dart';
import 'package:my_log/my_log.dart';

class RelayApplication implements ApplicationController {
  static const logPrefix = '[RelayApplication]';
  final VillageOverlay _overlay;
  final VillageDbHelper _db;
  final String upperAppName;
  final Map<String, AppMessageType> _mapOfAppMessageType = {};

  RelayApplication({
    required VillageOverlay overlay,
    required VillageDbHelper db,
    required this.upperAppName,
  })  : _overlay = overlay,
        _db = db {
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

    // A relay server simply saves the data to the database without any application-level merge logic
    // Currently we just log and accept it. Data validation and storage logic can be expanded here.
    switch (appType) {
      case AppMessageType.provideAppType:
        MyLogger.info('$logPrefix Received provideAppType data. Storing/Handling...');
        // _db.save... (In the future, we parse and save directly)
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