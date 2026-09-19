import 'dart:async';
import 'dart:io';

import 'package:libp2p/network/network_layer.dart';
import 'package:libp2p/network/peer.dart';
import 'package:libp2p/network/protocol/packet.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';

void main() {
  late SOTPNetworkLayer server;
  late RawDatagramSocket client;
  late StreamIterator<Packet> replies;
  final ip = InternetAddress.loopbackIPv4;
  final established = <Peer>[];
  var packetNumber = 0;

  Future<void> send(Packet packet) async {
    final received = Completer<void>();
    server.onReceivePacket = (_) { scheduleMicrotask(() => received.complete()); };
    client.send(packet.toBytes(), ip, server.realPort);
    await received.future.timeout(Duration(seconds: 2));
  }

  PacketConnect handshake(PacketType type, int source, [int destination = 0]) => PacketConnect(
    header: PacketHeader(type: type, destConnectionId: destination, packetNumber: ++packetNumber), sourceConnectionId: source,
  );

  Future<PacketConnect> connect(int id) async {
    await send(handshake(PacketType.connect, id));
    expect(await replies.moveNext().timeout(Duration(seconds: 2)), isTrue);
    final ack = replies.current as PacketConnect;
    expect(ack.getType(), PacketType.connectAck);
    expect(ack.header.destConnectionId, id);
    return ack;
  }

  Future<Peer> establish(int id) async {
    final ack = await connect(id);
    await send(handshake(PacketType.connected, id, ack.sourceConnectionId));
    return server.connectionPool.getConnectionById(ack.sourceConnectionId)!;
  }

  setUp(() async {
    MyLogger.initForTest(name: 'reconnect_test');
    established.clear();
    packetNumber = 0;
    server = SOTPNetworkLayer(localIp: ip, servicePort: 0, deviceId: 'server', newConnectCallback: established.add);
    await server.start();
    server.timer.cancel(); // Drive cleanup explicitly, without heartbeat timing races.
    client = await RawDatagramSocket.bind(ip, 0);
    replies = StreamIterator(client.where((event) => event == RawSocketEvent.read).map((_) {
      return PacketFactory(data: client.receive()!.data).getAbstractPacket()!;
    }));
  });

  tearDown(() async {
    for(final peer in server.connectionPool.getAllConnections()) {
      peer.onDisconnect = null;
    }
    server.stop();
    await replies.cancel();
    client.close();
  });

  test('duplicate connect preserves established peer and callbacks', () async {
    final old = await establish(101);
    var disconnected = 0;
    old.onDisconnect = (_) => disconnected++;
    await send(handshake(PacketType.connect, 101));
    expect(server.connectionPool.getAllConnections(), [old]);
    expect(server.incompletePool.getAllConnections(), isEmpty);
    expect(old.getStatus(), ConnectionStatus.established);
    expect(established, [old]);
    expect(disconnected, 0);
  });

  for(final status in [ConnectionStatus.established, ConnectionStatus.invalid, ConnectionStatus.shutdown]) {
    test('new source ID replaces $status peer before cleanup', () async {
      final old = await establish(101);
      if(status == ConnectionStatus.invalid) old.setInvalid();
      if(status == ConnectionStatus.shutdown) old.setShutdown();
      var disconnected = 0;
      old.onDisconnect = (peer) {
        expect(peer, same(old));
        expect(server.connectionPool.getConnectionById(old.getSourceId()), isNull);
        expect(server.incompletePool.getAllConnections(), isEmpty);
        disconnected++;
      };
      final fresh = await establish(202);
      expect(fresh, isNot(same(old)));
      expect(old.getStatus(), ConnectionStatus.shutdown);
      expect(old.controlQueue.getAllPackets(), isEmpty);
      expect(disconnected, status == ConnectionStatus.shutdown ? 0 : 1);
      expect(established, [old, fresh]);
      old.onClose();
      server.connectionPool.removeConnection(old);
      server.connectionPool.removeInvalidAndClosedConnections();
      server.incompletePool.removeInvalidAndClosedConnections();
      expect(server.connectionPool.getAllConnections(), [fresh]);
      expect(server.incompletePool.getAllConnections(), isEmpty);
      await send(PacketBye(tag: PacketBye.tagBye,
        header: PacketHeader(type: PacketType.bye, destConnectionId: old.getSourceId(), packetNumber: 20)));
      expect(fresh.getStatus(), ConnectionStatus.established);
    });
  }

  test('duplicate incomplete connect reuses peer but new ID replaces it and ignores old handshake', () async {
    final first = await connect(101);
    final old = server.incompletePool.getAllConnections().single;
    final duplicate = await connect(101);
    expect(duplicate.sourceConnectionId, first.sourceConnectionId);
    expect(server.incompletePool.getAllConnections(), [old]);
    final next = await connect(202);
    final fresh = server.incompletePool.getAllConnections().single;
    expect(fresh, isNot(same(old)));
    expect(old.getStatus(), ConnectionStatus.shutdown);
    expect(old.controlQueue.getAllPackets(), isEmpty);
    await send(handshake(PacketType.connected, 101, first.sourceConnectionId));
    await send(handshake(PacketType.connectAck, 101, first.sourceConnectionId));
    expect(fresh.getStatus(), ConnectionStatus.establishing);
    expect(fresh.getDestinationId(), 202);
    expect(established, isEmpty);
    await send(handshake(PacketType.connected, 202, next.sourceConnectionId));
    expect(server.connectionPool.getAllConnections(), [fresh]);
    expect(established, [fresh]);
  });

  for(final status in [ConnectionStatus.invalid, ConnectionStatus.shutdown]) {
    for(final completed in [false, true]) {
      test('same ID starts fresh after $status in ${completed ? "connection" : "incomplete"} pool', () async {
        Peer old;
        if(completed) {
          old = await establish(101);
        } else {
          await connect(101);
          old = server.incompletePool.getAllConnections().single;
        }
        if(status == ConnectionStatus.invalid) old.setInvalid();
        if(status == ConnectionStatus.shutdown) old.setShutdown();
        final fresh = await establish(101);
        expect(fresh, isNot(same(old)));
        expect(old.getStatus(), ConnectionStatus.shutdown);
        expect(old.controlQueue.getAllPackets(), isEmpty);
        server.connectionPool.removeInvalidAndClosedConnections();
        server.incompletePool.removeInvalidAndClosedConnections();
        expect(server.connectionPool.getAllConnections(), [fresh]);
        expect(server.incompletePool.getAllConnections(), isEmpty);
      });
    }
  }

  test('simultaneous outgoing connect learns remote ID without replacing peer', () async {
    final outgoing = server.connect(ip.address, client.port)!;
    expect(await replies.moveNext(), isTrue); // Initial outgoing connect.
    final ack = await connect(202);
    expect(ack.sourceConnectionId, outgoing.getSourceId());
    expect(outgoing.getDestinationId(), 202);
    await send(handshake(PacketType.connected, 202, outgoing.getSourceId()));
    expect(server.connectionPool.getAllConnections(), [outgoing]);
  });

  test('removing an old peer cannot remove a replacement with the same local ID', () {
    final pool = ConnectionPool();
    final old = Peer(ip: ip, port: 1, transport: (_, __, ___) => 0)..setSourceId(1);
    final fresh = Peer(ip: ip, port: 1, transport: (_, __, ___) => 0)..setSourceId(1)..setEstablished();
    pool.addConnection(old);
    pool.addConnection(fresh);
    pool.removeConnection(old);
    expect(pool.getConnectionById(1), same(fresh));
  });
}
