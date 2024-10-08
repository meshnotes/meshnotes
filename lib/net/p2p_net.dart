import 'package:libp2p/application/application_layer.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/dal/village_db.dart';
import 'package:libp2p/libp2p.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:my_log/my_log.dart';

startOverlay({bool asRoot=false}) async {
  startListening(8081);
}

runServer() {
  MyLogger.info('Run as server');
}

Future<Village> startVillage(String localPort, String serverList, String deviceId, UserPublicInfo userInfo, Function(VillagerNode) connectedCallback, VillageMessageHandler messageHandler) async {
  VillageDbHelper db = VillageDbHelper();
  db.init();

  int _localPort = int.tryParse(localPort)?? 0;
  var sponsors = _parseSponsors(serverList);
  final _overlay = VillageOverlay(
    userInfo: userInfo,
    sponsors: sponsors,
    port: _localPort,
    deviceId: deviceId,
    onNodeChanged: connectedCallback,
  );
  final village = Village(
    localPort: _localPort,
    sponsors: sponsors,
    overlay: _overlay,
    messageHandler: messageHandler,
    db: db,
    upperAppName: 'mesh_notes',
  );
  await village.start();
  return village;
}

List<String> _parseSponsors(String serverListStr) {
  var result = <String>[];
  var list = serverListStr.trim().split(',');
  for(var item in list) {
    if(item.isNotEmpty) {
      var address = item.trim();
      result.add(address);
    }
  }
  return result;
}