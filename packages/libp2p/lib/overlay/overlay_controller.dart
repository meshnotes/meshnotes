// abstract class OverlayController {
//   void onConnect(String id, String info, String status);
//   void onData(VillageData data);
// }

import 'package:libp2p/overlay/villager_node.dart';

abstract class ApplicationController {
  void onData(VillagerNode node, String app, String type, String data);
}