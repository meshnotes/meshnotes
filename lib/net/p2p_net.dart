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

Future<Village> startVillage({
  required String localPort,
  required String serverList,
  required String deviceId,
  required UserPublicInfo userInfo,
  required Function(VillagerNode) connectedCallback,
  required VillageMessageHandler messageHandler,
  bool useMulticast = false,
}) async {
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
    useMulticast: useMulticast,
  );
  final village = Village(
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