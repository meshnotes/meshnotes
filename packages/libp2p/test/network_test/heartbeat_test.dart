import 'dart:async';
import 'dart:io';

import 'package:libp2p/network/peer.dart';
import 'package:my_log/my_log.dart';
import 'package:libp2p/network/network_env.dart';
import 'package:libp2p/network/network_util.dart';
import 'package:test/test.dart';
import 'package:libp2p/network/network_layer.dart';

void main() {
  var serverPort = 8182;

  test('Heart beat', timeout: Timeout(Duration(seconds: 5)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var serverEstablished = Completer<bool>();
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      localPort: serverPort,
      newConnectCallback: (c) {
        serverEstablished.complete(true);
      },
      deviceId: 'x',
    );
    await server.start();

    var clientEstablished = Completer<bool>();
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      localPort: 0,
      connectOkCallback: (c) {
        clientEstablished.complete(true);
      },
      deviceId: 'x',
    );
    await client.start();

    var clientConnection = client.connect(loopbackIp, serverPort);
    clientConnection.maxHeartbeat = 1000;
    var now = networkNow();
    await serverEstablished.future;

    await Future.delayed(Duration(milliseconds: 2000));
    var lastContact = clientConnection.getLastContactTime();
    MyLogger.info('efantest: $lastContact, $now');
    expect(lastContact > now, true);
    now = networkNow();

    await Future.delayed(Duration(milliseconds: 2000));
    MyLogger.info('efantest: $lastContact, $now');
    lastContact = clientConnection.getLastContactTime();
    expect(lastContact > now, true);

    // Shutdown all networks
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Disconnect while heartbeat timeout 5 times', timeout: Timeout(Duration(seconds: 30)), () async {
    // 1. Start a new connection, and send data
    // 2. Set client heartbeat timeout to lower level, and make network environment drop all packets
    // 3. Disconnect after 5 heartbeat timeouts
    MyLogger.initForTest(name: 'libp2p_test');
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var serverEstablished = Completer<bool>();
    Peer? serverConnection;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      localPort: serverPort,
      newConnectCallback: (c) {
        serverEstablished.complete(true);
        serverConnection = c;
      },
      deviceId: 'x',
    );
    await server.start();

    var clientEstablished = Completer<bool>();
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      localPort: 0,
      connectOkCallback: (c) {
        clientEstablished.complete(true);
      },
      deviceId: 'x',
    );
    await client.start();

    var clientConnection = client.connect(loopbackIp, serverPort);
    await serverEstablished.future;
    List<int> data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

    var dataReceived = Completer<bool>();
    serverConnection!.setOnReceive((d) {
      MyLogger.info('Receive data: $d');
      expect(d.length, data.length);
      for(int i = 0; i < d.length; i++) {
        expect(d[i], data[i]);
      }
      dataReceived.complete(true);
    });
    clientConnection.sendData(data);
    await dataReceived.future;

    clientConnection.maxHeartbeat = 1000;
    var disconnected = Completer<bool>();
    clientConnection.onDisconnect = (_) {
      disconnected.complete(true);
    };
    client.setNetworkEnv(NetworkEnvSimulator.dropAll);
    await Future.delayed(Duration(milliseconds: 5000));

    await disconnected.future;

    // Shutdown all networks
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });
}