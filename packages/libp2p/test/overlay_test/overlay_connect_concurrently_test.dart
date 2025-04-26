import 'dart:async';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/network/network_env.dart';
import 'package:libp2p/network/protocol/packet.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';

/// These tests are used to test the scenario that two peers connect to each other at the same time
/// The correct behavior is that both sides will reuse the same Peer object
/// So there is no duplicate connection
void main() async {
  final deviceId1 = 'xxx';
  final deviceId2 = 'yyy';
  final port1 = 2222;
  final port2 = 2223;

  test('Both overlay instances connect to each other', timeout: Timeout(Duration(seconds: 10)), () async {
    MyLogger.initForTest(name: 'overlay_test');
    var delayedConnectNetworkEnv = NetworkEnvSimulator(sendHook: (socket, ip, port, packet) {
      // Send packet immediately if it is not a connect packet
      if(packet is! PacketConnect) return socket.send(packet.toBytes(), ip, port);
      PacketConnect connect = packet;
      if(connect.getType() != PacketType.connect) return socket.send(packet.toBytes(), ip, port);

      // Send connect packet after 2 seconds
      Timer(Duration(milliseconds: 2000), () {
        socket.send(packet.toBytes(), ip, port);
      });
      return 0;
    });


    VillagerNode? node1;
    var overlay1 = VillageOverlay(
      userInfo: UserPublicInfo(publicKey: 'test_key', userName: 'test', timestamp: 0),
      sponsors: ['127.0.0.1:$port2'],
      onNodeChanged: (VillagerNode _node) {
        if(node1 == null) {
          node1 = _node;
        }
        expect(node1!.ip, _node.ip);
        expect(node1!.port, _node.port);
      },
      deviceId: deviceId1,
      port: port1,
    );
    VillagerNode? node2;
    var overlay2 = VillageOverlay(
      userInfo: UserPublicInfo(publicKey: 'test_key', userName: 'test', timestamp: 0),
      sponsors: ['127.0.0.1:$port1'],
      onNodeChanged: (VillagerNode _node) {
        if(node2 == null) {
          node2 = _node;
        }
        expect(node2!.ip, _node.ip);
        expect(node2!.port, _node.port);
      },
      deviceId: deviceId2,
      port: port2,
    );

    overlay1.setNetworkEnvSimulator(delayedConnectNetworkEnv);
    overlay2.setNetworkEnvSimulator(delayedConnectNetworkEnv);

    await overlay1.start();
    await overlay2.start();

    await Future.delayed(Duration(milliseconds: 5000));

    final nodes1 = overlay1.getAllNodes();
    final nodes2 = overlay2.getAllNodes();
    expect(nodes1.length, 1);
    expect(nodes2.length, 1);
    expect(nodes1[0].port, port2);
    expect(nodes2[0].port, port1);

    overlay1.stop();
    overlay2.stop();
  });
}
