import 'dart:io';

import 'package:libp2p/network/peer.dart';
import 'package:libp2p/network/incomplete_pool.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';

void main() async {
  MyLogger.initForConsoleTest(name: 'libp2p_test');
  RawDatagramSocket socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  test('IncompletePool add and get', () {
    var ip = InternetAddress('1.2.3.4');
    int port = 8088;
    int id = 1111;
    var conn = Peer(ip: ip, port: port, transport: (data, ip, port) {
      return socket.send(data, ip, port);
    });
    var pool = IncompletePool();
    pool.addConnection(ip, port, id, conn);

    expect(pool.getAllConnections().length, 1);
    var result = pool.getConnection(ip, port, id);
    expect(result != null, true);
    expect(result!.ip, ip);
    expect(result.port, port);
  });
}