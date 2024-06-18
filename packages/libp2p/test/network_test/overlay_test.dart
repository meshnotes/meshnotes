import 'dart:async';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';

void main() {
  var serverPort = 8182;
  var serverDeviceId = 'server_device';
  var clientDeviceId = 'client_device';

  test('Connecting to non-exists upper node, try to exponential backoff after connection failed', timeout: Timeout(Duration(seconds: 60)), () async {
    MyLogger.initForTest(name: 'libp2p_test');

    var nonExistsNode = '1.2.3.4:12345';

    var clientCompleter1 = Completer<bool>();
    var clientCompleter2 = Completer<bool>();
    VillagerNode? clientNode;
    VillagerNode.defaultReconnectInterval = 1;
    var clientOverlay = VillageOverlay(
      userInfo: UserPublicInfo(publicKey: 'test_key', userName: 'test', timestamp: 0),
      sponsors: [nonExistsNode],
      port: 0,
      deviceId: clientDeviceId,
      onNodeChanged: (node) {
        clientNode = node;
        if(!clientCompleter1.isCompleted) {
          clientCompleter1.complete(true);
        } else if(!clientCompleter2.isCompleted){
          clientCompleter2.complete(true);
        }
      },
    );
    await clientOverlay.start();

    await clientCompleter1.future;
    expect(clientNode != null, true);
    expect(clientNode!.getStatus(), VillagerStatus.unknown);
    expect(clientNode!.currentReconnectIntervalInSeconds, VillagerNode.defaultReconnectInterval * 2);

    await clientCompleter2.future;
    expect(clientNode != null, true);
    expect(clientNode!.getStatus(), VillagerStatus.unknown);
    expect(clientNode!.currentReconnectIntervalInSeconds, VillagerNode.defaultReconnectInterval * 4);

    clientOverlay.stop();
  });
}