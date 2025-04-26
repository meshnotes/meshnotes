import 'dart:async';
// import 'dart:io';
// import 'package:libp2p/network/peer.dart';
// import 'package:my_log/my_log.dart';
import 'package:libp2p/network/network_env.dart';
import 'package:libp2p/network/protocol/packet.dart';
import 'package:libp2p/network/network_layer.dart';
import 'dart:io';

import 'package:libp2p/network/peer.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';

/// These tests are used to test the scenario that two peers connect to each other at the same time
/// The correct behavior is that both sides will reuse the same Peer object
/// So there is no duplicate connection
void main() async {
  final serverPort = 8181;
  final clientPort = 8182;
  final loopbackIp = "127.0.0.1";
  final clientDeviceId = 'yyy';
  final serverDeviceId = 'xxx';

  test('Connect at the same time, one side may receive connect when peer is establishing', timeout: Timeout(Duration(seconds: 5)), () async {
    // 0. Open server and client
    // 1. Set client network environment to delay sending connect packet
    // 2. Send connect in both server and client
    // 3. Expect to get connect complete in both server and client
    // 4. There is only one Peer object in each side
    MyLogger.initForTest(name: 'libp2p_test');
    var serverIp = InternetAddress.anyIPv4;

    var serverEstablished = Completer<bool>();
    Peer? serverConnection;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      deviceId: serverDeviceId,
      newConnectCallback: (c) {
        serverEstablished.complete(true);
        if(serverConnection == null) {
          serverConnection = c;
        } else {
          MyLogger.info('Server received duplicate connect packet in newConnectCallback');
          expect(serverConnection, c);
        }
      },
      connectOkCallback: (c) {
        serverEstablished.complete(true);
        if(serverConnection == null) {
          serverConnection = c;
        } else {
          MyLogger.info('Server received duplicate connect packet in connectOkCallback');
          expect(serverConnection, c);
        }
      },
    );
    await server.start();

    var clientEstablished = Completer<bool>();
    Peer? clientConnection;
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: clientPort,
      deviceId: clientDeviceId,
      connectOkCallback: (c) {
        clientEstablished.complete(true);
        if(clientConnection == null) {
          clientConnection = c;
        } else {
          MyLogger.info('Client received duplicate connect packet in connectOkCallback');
          expect(clientConnection, c);
        }
      },
      newConnectCallback: (c) {
        clientEstablished.complete(true);
        if(clientConnection == null) {
          clientConnection = c;
        } else {
          MyLogger.info('Client received duplicate connect packet in newConnectCallback');
          expect(clientConnection, c);
        }
      },
    );
    await client.start();
    var clientOriginalConnection = client.connect(loopbackIp, serverPort);
    expect(clientOriginalConnection != null, true);

    var serverOriginalConnection = server.connect(loopbackIp, clientPort);
    expect(serverOriginalConnection != null, true);
    await Future.wait([serverEstablished.future, clientEstablished.future]);
    MyLogger.info('Server and client established');

    server.stop();
    client.stop();
  });

  test('Connect at the same time, receive connect packet after 2 seconds', timeout: Timeout(Duration(seconds: 5)), () async {
    // 0. Open server and client
    // 1. Set client network environment to delay sending connect packet
    // 2. Send connect in both server and client
    // 3. Expect to get connect complete in both server and client
    // 4. There is only one Peer object in each side
    MyLogger.initForTest(name: 'libp2p_test');
    var serverIp = InternetAddress.anyIPv4;

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
    var serverEstablished = Completer<bool>();
    Peer? serverConnection;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      deviceId: serverDeviceId,
      newConnectCallback: (c) {
        serverEstablished.complete(true);
        if(serverConnection == null) {
          serverConnection = c;
        } else {
          MyLogger.info('Server received duplicate connect packet in newConnectCallback');
          expect(serverConnection, c);
        }
      },
      connectOkCallback: (c) {
        serverEstablished.complete(true);
        if(serverConnection == null) {
          serverConnection = c;
        } else {
          MyLogger.info('Server received duplicate connect packet in connectOkCallback');
          expect(serverConnection, c);
        }
      },
    );
    server.setNetworkEnv(delayedConnectNetworkEnv);
    await server.start();

    var clientEstablished = Completer<bool>();
    Peer? clientConnection;
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: clientPort,
      deviceId: clientDeviceId,
      connectOkCallback: (c) {
        clientEstablished.complete(true);
        if(clientConnection == null) {
          clientConnection = c;
        } else {
          MyLogger.info('Client received duplicate connect packet in connectOkCallback');
          expect(clientConnection, c);
        }
      },
      newConnectCallback: (c) {
        clientEstablished.complete(true);
        if(clientConnection == null) {
          clientConnection = c;
        } else {
          MyLogger.info('Client received duplicate connect packet in newConnectCallback');
          expect(clientConnection, c);
        }
      },
    );
    client.setNetworkEnv(delayedConnectNetworkEnv);
    await client.start();
    var clientOriginalConnection = client.connect(loopbackIp, serverPort);
    expect(clientOriginalConnection != null, true);

    var serverOriginalConnection = server.connect(loopbackIp, clientPort);
    expect(serverOriginalConnection != null, true);
    await Future.wait([serverEstablished.future, clientEstablished.future]);
    MyLogger.info('Server and client established');

    server.stop();
    client.stop();
  });
}
