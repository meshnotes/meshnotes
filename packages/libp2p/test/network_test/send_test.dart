import 'dart:async';
import 'dart:io';

import 'package:libp2p/network/peer.dart';
import 'package:my_log/my_log.dart';
import 'package:libp2p/network/network_env.dart';
import 'package:libp2p/network/protocol/frame.dart';
import 'package:libp2p/network/protocol/packet.dart';
import 'package:test/test.dart';
import 'package:libp2p/network/network_layer.dart';

void main() {
  final serverPort = 8181;
  final loopbackIp = "127.0.0.1";

  test('Send small object', timeout: Timeout(Duration(seconds: 5)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    var serverIp = InternetAddress.anyIPv4;
    var serverEstablished = Completer<bool>();
    Peer? serverConnection;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      deviceId: 'x',
      newConnectCallback: (c) {
        serverEstablished.complete(true);
        serverConnection = c;
      },
    );
    await server.start();

    var clientEstablished = Completer<bool>();
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: 0,
      deviceId: 'x',
      connectOkCallback: (c) {
        clientEstablished.complete(true);
      },
    );
    await client.start();

    var clientConnection = client.connect(loopbackIp, serverPort);
    expect(clientConnection != null, true);
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
    clientConnection!.sendData(data);
    await dataReceived.future;

    // Shutdown all networks
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Timeout and resend object', timeout: Timeout(Duration(seconds: 10)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    var serverIp = InternetAddress.anyIPv4;
    var serverEstablished = Completer<bool>();
    Peer? serverConnection;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      deviceId: 'x',
      newConnectCallback: (c) {
        serverEstablished.complete(true);
        serverConnection = c;
      },
    );
    await server.start();
    server.setDebugIgnoreData(true);

    var clientEstablished = Completer<bool>();
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: 0,
      deviceId: 'x',
      connectOkCallback: (c) {
        clientEstablished.complete(true);
      },
    );
    await client.start();

    var clientConnection = client.connect(loopbackIp, serverPort);
    expect(clientConnection != null, true);
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
    clientConnection!.sendData(data);

    await Future.delayed(Duration(seconds: 4));
    expect(clientConnection.retryQueue.messages.length, 1);
    expect(clientConnection.retryQueue.messages[0].getResendCount(), 1);
    expect(dataReceived.isCompleted, false);

    // Resume network layer, and wait for data receive completely
    server.setDebugIgnoreData(false);
    await dataReceived.future;

    // Shutdown all networks
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Send big object(1M)', timeout: Timeout(Duration(seconds: 30)), () async {
    await testSendObject(loopbackIp, serverPort, 1024 * 1024);
  });

  test('Send very big object(16M)', timeout: Timeout(Duration(seconds: 30)), () async {
    await testSendObject(loopbackIp, serverPort, 1024 * 1024 * 16);
  });

  test('Send very very big object(128M)', timeout: Timeout(Duration(seconds: 300)), () async {
    await testSendObject(loopbackIp, serverPort, 1024 * 1024 * 128, needLog: false);
  });

  test('Receive out-of-order object', timeout: Timeout(Duration(seconds: 10)), () async {
    // 0. Open server and client
    // 1. Set client network environment to ignore second packet of first object
    // 2. Send first object, delay 1 second, and then send second object
    // 3. Expect to get second object first
    // 4. Recover network environment
    // 5. Expect to get first object
    MyLogger.initForTest(name: 'libp2p_test');
    var serverIp = InternetAddress.anyIPv4;

    var serverEstablished = Completer<bool>();
    Peer? serverConnection;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      deviceId: 'x',
      newConnectCallback: (c) {
        serverEstablished.complete(true);
        serverConnection = c;
      },
    );
    await server.start();

    var clientEstablished = Completer<bool>();
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: 0,
      deviceId: 'x',
      connectOkCallback: (c) {
        clientEstablished.complete(true);
      },
    );
    await client.start();
    var clientConnection = client.connect(loopbackIp, serverPort);
    expect(clientConnection != null, true);
    await serverEstablished.future;

    // Set network simulator to ignore second packet of first object
    client.setNetworkEnv(NetworkEnvSimulator(sendHook: (socket, ip, port, packet) {
      if(packet is! PacketData) return socket.send(packet.toBytes(), ip, port);
      PacketData packetData = packet;
      var frames = packetData.frames;
      for(var frame in frames) {
        if(frame.type != FrameType.dataFrame) continue;
        var data = frame as FrameData;
        if(data.objId == 0 && data.seqNum == 1) {
          return 0;
        }
      }
      return socket.send(packet.toBytes(), ip, port);
    }));

    final dataSize = 5000;
    final firstObjectData = 1;
    final secondObjectData = 2;
    List<int> firstData = List.filled(dataSize, firstObjectData);
    List<int> secondData = List.filled(dataSize, secondObjectData);

    var firstComplete = Completer<bool>();
    var secondComplete = Completer<bool>();
    serverConnection!.setOnReceive((d) {
      if(d.length < 1024) {
        MyLogger.info('Receive data: $d');
      } else {
        MyLogger.info('Receive data(too long) length=${d.length}');
      }
      var data = d[0];
      expect(d.length, dataSize);
      for(int i = 0; i < d.length; i++) {
        expect(d[i], data);
      }
      if(data == firstObjectData) {
        MyLogger.info('[Test] Receive first object');
        firstComplete.complete(true);
      } else if(data == secondObjectData) {
        MyLogger.info('[Test] Receive second object');
        secondComplete.complete(true);
      }
    });
    clientConnection!.sendData(firstData);
    await Future.delayed(Duration(seconds: 1));
    clientConnection.sendData(secondData);
    // Expect to get second object complete first
    await secondComplete.future;
    // First object is not complete yet
    expect(firstComplete.isCompleted, false);
    // Recover network environment
    client.setNetworkEnv(NetworkEnvSimulator.acceptAll);
    // Expect to get first object complete after first one
    await firstComplete.future;

    await Future.delayed(Duration(seconds: 1));

    // Shutdown all networks
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });
}

Future<void> testSendObject(String localIp, int serverPort, int dataSize, {bool needLog=true}) async {
  MyLogger.initForTest(debug: needLog, name: 'libp2p_test');
  var serverIp = InternetAddress.anyIPv4;
  var serverEstablished = Completer<bool>();
  Peer? serverConnection;
  var server = SOTPNetworkLayer(
    localIp: serverIp,
    servicePort: serverPort,
    deviceId: 'x',
    newConnectCallback: (c) {
      serverEstablished.complete(true);
      serverConnection = c;
    },
  );
  await server.start();

  var clientEstablished = Completer<bool>();
  var client = SOTPNetworkLayer(
    localIp: InternetAddress(localIp),
    servicePort: 0,
    deviceId: 'x',
    connectOkCallback: (c) {
      clientEstablished.complete(true);
    },
  );
  await client.start();

  var clientConnection = client.connect(localIp, serverPort);
  expect(clientConnection != null, true);
  await serverEstablished.future;
  List<int> bigData = List.filled(dataSize, 0);
  for(int i = 0; i < dataSize; i++) {
    bigData[i] = i & 0xFF;
  }

  var dataReceived = Completer<bool>();
  serverConnection!.setOnReceive((d) {
    if(needLog) {
      if(d.length < 1024) {
        MyLogger.info('Receive data: $d');
      } else {
        MyLogger.info('Receive data(too long) length=${d.length}');
      }
    }
    expect(d.length, bigData.length);
    for(int i = 0; i < d.length; i++) {
      expect(d[i], bigData[i]);
    }
    dataReceived.complete(true);
  });
  clientConnection!.sendData(bigData);
  await dataReceived.future;

  // Shutdown all networks
  server.stop();
  client.stop();
  expect(server.getStatus(), NetworkStatus.invalid);
  expect(client.getStatus(), NetworkStatus.invalid);
}