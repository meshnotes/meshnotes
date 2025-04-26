import 'dart:io';

import 'package:libp2p/network/peer.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';

void main() async {
  MyLogger.initForConsoleTest(name: 'libp2p_test');
  RawDatagramSocket socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  test('Connection pool add test', () async {
    var pool = ConnectionPool();
    var ip = InternetAddress('1.2.3.4');
    int port = 1234;
    const connectionId = 123456789;
    var connection = Peer(ip: ip, port: port, transport: (packet, ip, port) {
      return socket.send(packet.toBytes(), ip, port);
    });
    pool.addConnection(connection);

    expect(pool.getConnectionById(connectionId), null);

    connection.setSourceId(connectionId);
    pool.addConnection(connection);
    expect(pool.getConnectionById(connectionId), connection);
  });

  test('Connection pool deletion test', () {
    var pool = ConnectionPool();
    var ip = InternetAddress('127.0.0.1');
    int port = 8000;
    const connectionId = 9876543210;
    var connection = Peer(ip: ip, port: port, transport: (packet, ip, port) {
      return socket.send(packet.toBytes(), ip, port);
    });
    connection.setSourceId(connectionId);

    pool.addConnection(connection);
    expect(pool.getConnectionById(connectionId), connection);

    pool.removeConnection(connection);
    expect(pool.getConnectionById(connectionId), null);
  });
}