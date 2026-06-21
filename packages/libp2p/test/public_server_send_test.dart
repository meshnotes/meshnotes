import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/overlay/overlay_controller.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';

class _MockApp implements ApplicationController {
  @override
  void onData(VillagerNode node, String appName, String type, String data) {}
}

class _MockOverlay extends VillageOverlay {
  final List<VillagerNode> mockNodes;
  final List<VillagerNode> sentNodes = [];

  _MockOverlay({
    required bool allowSendingToPublicServer,
    required this.mockNodes,
  }): super(
    userInfo: UserPublicInfo(publicKey: 'user_key', userName: 'test', timestamp: 0),
    sponsors: [],
    onNodeChanged: (_){},
    allowSendingToPublicServer: allowSendingToPublicServer,
  );

  @override
  List<VillagerNode> getAllNodes() => mockNodes;

  @override
  void sendData(String appKey, ApplicationController app, VillagerNode node, String type, String data) {
    sentNodes.add(node);
  }
}

void main() {
  MyLogger.initForConsoleTest(name: 'public_server_send_test');

  test('sendToAllNodesOfUser filters different public keys by default', () {
    final sameUserNode = VillagerNode(host: '127.0.0.1', port: 1001)..publicKey = 'user_key';
    final publicServerNode = VillagerNode(host: '127.0.0.1', port: 1002)..publicKey = 'server_key';
    final overlay = _MockOverlay(
      allowSendingToPublicServer: false,
      mockNodes: [sameUserNode, publicServerNode],
    );

    overlay.sendToAllNodesOfUser('app', _MockApp(), 'publish', 'data');

    expect(overlay.sentNodes, [sameUserNode]);
  });

  test('sendToAllNodesOfUser sends to different public keys when public server is allowed', () {
    final sameUserNode = VillagerNode(host: '127.0.0.1', port: 1001)..publicKey = 'user_key';
    final publicServerNode = VillagerNode(host: '127.0.0.1', port: 1002)..publicKey = 'server_key';
    final overlay = _MockOverlay(
      allowSendingToPublicServer: true,
      mockNodes: [sameUserNode, publicServerNode],
    );

    overlay.sendToAllNodesOfUser('app', _MockApp(), 'publish', 'data');

    expect(overlay.sentNodes, [sameUserNode, publicServerNode]);
  });
}
