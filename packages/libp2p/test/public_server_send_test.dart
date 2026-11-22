import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:keygen/keygen.dart';
import 'package:libp2p/network/peer.dart';
import 'package:libp2p/network/network_layer.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/application/application_layer.dart';
import 'package:libp2p/dal/village_db.dart';
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
  final List<String> sentPayloads = [];

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
    sentPayloads.add(data);
  }
}

class _MockPeer extends Peer {
  final int connectionId;
  _MockPeer(this.connectionId): super(ip: InternetAddress.loopbackIPv4, port: 1001, transport: (_, __, ___) => 0);
  @override
  int getSourceId() => connectionId;
}

Future<String> _businessReply(String transactionId) => Isolate.run(() => transactionId);

final _signing = SigningWrapper.random();

String _transaction(String id, TransactionStatus status, TransactionContentType type, String data, {int? count}) {
  final message = TransactionMessage(transactionId: id, status: status, contentType: type, data: data,
    userPublicId: _signing.getCompressedPublicKey(), signature: '', objectCount: count);
  message.signature = _signing.sign(HashUtil.hashText(message.toSignableString()));
  return jsonEncode(message);
}

String _query(String? transactionId) {
  final data = jsonEncode({'versions': ['version-1']});
  final payload = jsonEncode(UncipherMessage(userPublicId: _signing.getCompressedPublicKey(), data: data,
    signature: _signing.sign(HashUtil.hashText(data))));
  if(transactionId == null) return payload;
  return _transaction(transactionId, TransactionStatus.request, TransactionContentType.uncipher, payload);
}

String _provide(String transactionId, {bool complete = false, bool failed = false}) {
  final payload = jsonEncode(CipherMessages(userPublicId: _signing.getCompressedPublicKey(), resources: [], signature: 'inner'));
  return _transaction(transactionId, failed ? TransactionStatus.failed : complete ? TransactionStatus.completed : TransactionStatus.partial,
    TransactionContentType.cipher, payload, count: complete ? 0 : null);
}

void main() {
  MyLogger.initForConsoleTest(name: 'public_server_send_test');

  test('query response returns only to the requesting connection across isolates', () async {
    final target = VillagerNode(host: '127.0.0.1', port: 1001)..nodeId = 'requester'..publicKey = _signing.getCompressedPublicKey();
    final other = VillagerNode(host: '127.0.0.1', port: 1002)..nodeId = 'other'..publicKey = _signing.getCompressedPublicKey();
    target.setPeer(_MockPeer(123));
    target.setConnected();
    other.setConnected();
    final overlay = _MockOverlay(allowSendingToPublicServer: true, mockNodes: [target, other]);
    final village = Village(sponsors: [], overlay: overlay, db: VillageDbHelper(), messageHandler: VillageMessageHandler(), upperAppName: 'app');
    String? received;
    final queryData = ' \n${_query(null)} ';
    village.messageHandler.handleQueryFromNode = (sender, data, stats, transactionId) {
      expect(data, queryData); // Preserve the exact inner string, including whitespace.
      received = transactionId;
    };
    village.onData(target, 'app', 'query', _transaction('query-1', TransactionStatus.request, TransactionContentType.uncipher, queryData));
    expect(received!, 'query-1');
    expect(village.isTransactionalQuery(received!), isTrue);
    final transactionId = await _businessReply(received!);
    expect(transactionId, 'query-1');
    // Only the transaction ID crosses the isolate; routing stays in the protocol layer.
    village.sendVersions('opaque response bytes' * 10, TimeCostStatistics(), transactionId, false);
    village.sendVersionTree('opaque final bytes' * 10, TimeCostStatistics(), transactionId, true);
    expect(overlay.sentNodes, [target, target]);
    expect(overlay.sentPayloads, ['opaque response bytes' * 10, 'opaque final bytes' * 10]);
    village.sendVersions('opaque response bytes' * 10, TimeCostStatistics(), transactionId, false);
    expect(overlay.sentNodes, [target, target]);

    village.messageHandler.handleQueryFromNode = (sender, data, stats, transactionId) { received = transactionId; };
    for(final state in ['disconnected', 'replaced', 'removed']) {
      target.setConnected();
      target.setPeer(_MockPeer(123));
      village.onData(target, 'app', 'query', _query(state));
      final staleReply = await _businessReply(received!);
      if(state == 'disconnected') {
        target.setLost();
      }
      if(state == 'replaced') {
        target.setPeer(_MockPeer(456));
      }
      if(state == 'removed') {
        overlay.mockNodes.remove(target);
      }
      expect(() => village.sendVersions(_provide(state), TimeCostStatistics(), staleReply, false), returnsNormally);
      expect(overlay.sentNodes, [target, target]);
    }
  });

  test('transaction routes reject collisions and expire without affecting newer attempts', () {
    final timers = <Timer>[];
    final expirations = <void Function()>[];
    runZoned(() {
      final target = VillagerNode(host: '127.0.0.1', port: 1001)..nodeId = 'requester'..publicKey = _signing.getCompressedPublicKey();
      final other = VillagerNode(host: '127.0.0.1', port: 1002)..nodeId = 'other'..publicKey = _signing.getCompressedPublicKey();
      target.setPeer(_MockPeer(123));
      target.setConnected();
      other.setPeer(_MockPeer(456));
      other.setConnected();
      final overlay = _MockOverlay(allowSendingToPublicServer: true, mockNodes: [target, other]);
      final replies = <String>[];
      final handler = VillageMessageHandler()..handleQueryFromNode = (sender, data, stats, transactionId) { replies.add(transactionId); };
      final village = Village(sponsors: [], overlay: overlay, db: VillageDbHelper(), messageHandler: handler, upperAppName: 'app');
      try {
        village.onData(target, 'app', 'query', _query('old'));
        village.onData(other, 'app', 'query', _query('old'));
        village.onData(target, 'app', 'query', _query('old'));
        village.onData(other, 'another-app', 'query', _query('ignored'));
        expect(replies, ['old']);
        village.onData(other, 'app', 'query', _query('new'));
        timers.first.cancel();
        expirations.first();
        village.sendVersions(_provide('old'), TimeCostStatistics(), replies.first, false);
        expect(overlay.sentNodes, isEmpty);
        // Old completion cannot close or redirect the new transaction.
        village.sendVersions(_provide('old', complete: true), TimeCostStatistics(), replies.first, true);
        expect(overlay.sentNodes, isEmpty);
        final previousTimeout = timers.last;
        village.sendVersions(_provide('new'), TimeCostStatistics(), replies.last, false);
        expect(previousTimeout.isActive, isFalse);
        expect(timers.last.isActive, isTrue);
        village.sendVersions(_provide('new', complete: true, failed: true), TimeCostStatistics(), replies.last, true);
        village.sendVersions(_provide('new'), TimeCostStatistics(), replies.last, false);
        expect(overlay.sentNodes, [other, other]);
        expect(timers.any((timer) => timer.isActive), isFalse);
      } finally {
        for(final timer in timers) { timer.cancel(); }
      }
    }, zoneSpecification: ZoneSpecification(createTimer: (self, parent, zone, duration, callback) {
      expect(duration, const Duration(minutes: 5));
      expirations.add(callback);
      final timer = parent.createTimer(zone, duration, callback);
      timers.add(timer);
      return timer;
    }));
  });

  test('legacy queries get distinct local transactions and failure completion releases the route', () {
    final target = VillagerNode(host: '127.0.0.1', port: 1001)..nodeId = 'requester'..publicKey = _signing.getCompressedPublicKey();
    target.setPeer(_MockPeer(123));
    target.setConnected();
    final overlay = _MockOverlay(allowSendingToPublicServer: true, mockNodes: [target]);
    final replies = <String>[];
    final handler = VillageMessageHandler()..handleQueryFromNode = (sender, data, stats, transactionId) { replies.add(transactionId); };
    final village = Village(sponsors: [], overlay: overlay, db: VillageDbHelper(), messageHandler: handler, upperAppName: 'app');
    village.onData(target, 'app', 'query', _query(null));
    village.onData(target, 'app', 'query', _query(null));
    expect(replies.toSet(), hasLength(2));
    for(final transactionId in replies) {
      expect(village.isTransactionalQuery(transactionId), isFalse);
      final payload = jsonEncode(CipherMessages(userPublicId: _signing.getCompressedPublicKey(), resources: [], signature: 'inner'));
      village.sendVersions(payload, TimeCostStatistics(), transactionId, true);
      village.sendVersions(_provide(transactionId), TimeCostStatistics(), transactionId, false);
    }
    expect(overlay.sentNodes, [target, target]);
    for(final data in overlay.sentPayloads) {
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      expect(TransactionMessage.isTransaction(decoded), isFalse);
      expect(CipherMessages.fromJson(decoded).resources, isEmpty);
    }
  });

  test('transaction query routing rejects invalid roles types and tampering without reserving the ID', () {
    final target = VillagerNode(host: '127.0.0.1', port: 1001)..nodeId = 'requester'..publicKey = _signing.getCompressedPublicKey();
    target.setPeer(_MockPeer(123));
    target.setConnected();
    final overlay = _MockOverlay(allowSendingToPublicServer: true, mockNodes: [target]);
    final replies = <String>[];
    final handler = VillageMessageHandler()..handleQueryFromNode = (sender, data, stats, id) { replies.add(id); };
    final village = Village(sponsors: [], overlay: overlay, db: VillageDbHelper(), messageHandler: handler, upperAppName: 'app');
    final ordinary = _query(null);
    for(final payload in [
      _transaction('check', TransactionStatus.request, TransactionContentType.cipher, ordinary),
      _transaction('check', TransactionStatus.completed, TransactionContentType.uncipher, ordinary, count: 0),
      _query('check').replaceFirst('"status":"request"', '"status":"unknown"'),
      _query('check').replaceFirst('"content_type":"uncipher"', '"content_type":"unknown"'),
      _query('check').replaceFirst('"transaction_id":"check"', '"transaction_id":"tampered"'),
    ]) {
      expect(() => village.onData(target, 'app', 'query', payload), returnsNormally);
      expect(replies, isEmpty);
    }
    village.onData(target, 'app', 'query', _query('check'));
    expect(replies, ['check']);
    village.sendVersions(_provide('check', complete: true), TimeCostStatistics(), 'check', true);
    expect(overlay.sentNodes, [target]);
    // The protocol layer must not parse the inner payload, even when it is not valid JSON.
    handler.handleQueryFromNode = (sender, data, stats, id) {
      expect(data, 'not-json');
      replies.add(id);
    };
    village.onData(target, 'app', 'query', _transaction('opaque', TransactionStatus.request, TransactionContentType.uncipher, 'not-json'));
    expect(replies, ['check', 'opaque']);
    village.sendVersions(_provide('opaque', complete: true), TimeCostStatistics(), 'opaque', true);
  });

  test('signed cipher and uncipher transaction envelopes survive UDP fragmentation', timeout: Timeout(Duration(seconds: 10)), () async {
    var received = Completer<List<int>>();
    final connected = Completer<void>();
    final server = SOTPNetworkLayer(localIp: InternetAddress.loopbackIPv4, servicePort: 8181, deviceId: 'tx-server',
      newConnectCallback: (peer) { peer.setOnReceive((bytes) { received.complete(bytes); }); });
    final client = SOTPNetworkLayer(localIp: InternetAddress.loopbackIPv4, servicePort: 0, deviceId: 'tx-client',
      connectOkCallback: (_) { connected.complete(); });
    addTearDown(() { server.stop(); client.stop(); });
    await server.start();
    await client.start();
    final peer = client.connect('127.0.0.1', 8181)!;
    await connected.future;
    final largeContent = 'transaction-content-' * 1000;
    for(final type in TransactionContentType.values) {
      final inner = type == TransactionContentType.cipher
        ? jsonEncode(CipherMessages(userPublicId: _signing.getCompressedPublicKey(), signature: 'inner', resources: [
            CipherMessage(key: 'object', subKey: '', timestamp: 1, data: largeContent, signature: 'owner')]))
        : jsonEncode(UncipherMessage(userPublicId: _signing.getCompressedPublicKey(), data: largeContent, signature: 'inner'));
      final payload = _transaction('udp-${type.name}', TransactionStatus.completed, type, inner, count: 1);
      expect(peer.sendData(utf8.encode(payload)), isTrue);
      final bytes = await received.future;
      expect(utf8.decode(bytes), payload);
      final message = TransactionMessage.fromJson(jsonDecode(utf8.decode(bytes)));
      expect(VerifyingWrapper.loadKey(message.userPublicId).ver(HashUtil.hashText(message.toSignableString()), message.signature), isTrue);
      if(type == TransactionContentType.cipher) {
        expect(message.parseCipher().resources.single.data, largeContent);
      } else {
        expect(message.parseUncipher().data, largeContent);
      }
      received = Completer<List<int>>();
    }
  });

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
