import 'dart:async';
import 'dart:io';

import 'package:libp2p/network/peer.dart';
import 'package:my_log/my_log.dart';
import 'package:libp2p/network/network_env.dart';
import 'package:libp2p/network/protocol/packet.dart';
import 'package:test/test.dart';
import 'package:libp2p/network/network_layer.dart';

void main() {
  var serverPort = 8081;
  var serverDeviceId = 'server_device';
  var clientDeviceId = 'client_device';
  test('Network connection in normal environment', timeout: Timeout(Duration(seconds: 5)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    /// 1. Start network services server and client
    /// 2. Connect to server
    /// 3. Check connection status
    /// 4. Check retry queue
    /// 5. Shutdown network services
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var serverEstablished = Completer<bool>();
    var lastClientPacketNumber = 0;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      newConnectCallback: (c) {
        serverEstablished.complete(true);
      },
      deviceId: serverDeviceId,
      onReceivePacket: (p) {
        final packetNumber = p.getPacketNumber();
        if(lastClientPacketNumber != 0) {
          // Make sure new arriving packet's packet_number is greater than that of previous one
          expect(packetNumber, lastClientPacketNumber + 1);
        }
        lastClientPacketNumber = packetNumber;
        MyLogger.info('[Test] client packetNumber=$packetNumber');
      },
    );
    await server.start();

    var clientEstablished = Completer<bool>();
    int? sourceId, destId;
    var lastServerPacketNumber = 0;
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: 0,
      connectOkCallback: (c) {
        sourceId = c.getSourceId();
        destId = c.getDestinationId();
        clientEstablished.complete(true);
      },
      deviceId: clientDeviceId,
      onReceivePacket: (p) {
        final packetNumber = p.getPacketNumber();
        if(lastServerPacketNumber != 0) {
          // Make sure new arriving packet's packet_number is greater than that of previous one
          expect(packetNumber, lastServerPacketNumber + 1);
        }
        lastServerPacketNumber = packetNumber;
        MyLogger.info('[Test] server packetNumber=$packetNumber');
      },
    );
    await client.start();
    client.connect(loopbackIp, serverPort);
    bool connectedResult = await clientEstablished.future && await serverEstablished.future; // Wait for completions of both server side and client side

    expect(connectedResult, true);
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);
    expect(sourceId != null, true);
    expect(destId != null, true);

    var clientConnection = client.connectionPool.getConnectionById(sourceId!);
    expect(clientConnection != null, true);
    expect(clientConnection!.getSourceId(), sourceId);
    expect(clientConnection.getDestinationId(), destId);
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getStatus(), ConnectionStatus.established);

    var serverConnection = server.connectionPool.getConnectionById(destId!);
    expect(serverConnection != null, true);
    expect(serverConnection!.getDestinationId(), sourceId);
    expect(serverConnection.getSourceId(), destId);
    expect(serverConnection.getStatus(), ConnectionStatus.established);

    // 4. Check retry queue
    expect(serverConnection.retryQueue.messages.length, 0);
    expect(clientConnection.retryQueue.messages.length, 0);

    // 5. Shutdown network services
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Network connect resend while server not receiving connect', timeout: Timeout(Duration(seconds: 30)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    /// 1. Start network services server and client
    /// 2. Set client network environment to be "drop all packets"
    /// 3. Connect to server
    /// 4. Check connection status
    /// 5. Wait for timeout
    /// 6. Check connection retry status
    /// 7. Set client network environment to normal, and then wait for retry
    /// 8. Check status again
    /// 9. Shutdown network services
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var serverEstablished = Completer<bool>();
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort, newConnectCallback: (c) {
        serverEstablished.complete(true);
      },
      deviceId: serverDeviceId,
    );
    await server.start();

    var timeBeforeSend = DateTime.now().millisecondsSinceEpoch;
    int? sourceId, destId;
    var clientEstablished = Completer<bool>();
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: 0,
      connectOkCallback: (c) {
        sourceId = c.getSourceId();
        destId = c.getDestinationId();
        clientEstablished.complete(true);
      },
      deviceId: clientDeviceId,
    );
    await client.start();
    client.setNetworkEnv(NetworkEnvSimulator.dropAll);
    client.connect(loopbackIp, serverPort);

    // Wait 1 second, and check connection pool
    await Future.delayed(Duration(milliseconds: 1000));
    var timeAfterSend = DateTime.now().millisecondsSinceEpoch;
    // Only 1 connection in client's pool, and destId must be 0, status is "initializing"
    var clientIncompleteConnections = client.incompletePool.getAllConnections();
    expect(clientIncompleteConnections.length, 1);
    var clientConnection = clientIncompleteConnections[0];
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getSourceId() != 0, true);
    expect(clientConnection.getDestinationId(), 0);
    expect(clientConnection.getStatus(), ConnectionStatus.establishing);
    // The control queue of client side connection must have exactly 1 connect packet, retry count is 0
    var clientControlQueue = clientConnection.controlQueue;
    var clientControlQueuePackets = clientControlQueue.getAllPackets();
    expect(clientControlQueuePackets.length, 1);
    expect(clientControlQueue.getConnectRetryCount(), 0);
    var clientLastConnectTime = clientControlQueue.getLastConnectTime();
    expect(clientLastConnectTime >= timeBeforeSend, true);
    expect(clientLastConnectTime < timeAfterSend, true);
    var msg = clientControlQueuePackets[0];
    final initSendPacketNumber = clientConnection.sendPacketNumber;
    expect(msg.getType(), PacketType.connect);

    // 5. Wait for timeout
    await Future.delayed(Duration(milliseconds: client.maxTimeout));
    var timeAfterTimeout = DateTime.now().millisecondsSinceEpoch;
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);

    // 6. Check connection retry status
    // The incomplete connection pool in server network_layer must be empty
    var serverIncompleteConnections = server.incompletePool.getAllConnections();
    expect(serverIncompleteConnections.length, 0);
    // The retry count of client side connection must be greater than or equal to 1
    expect(clientControlQueue.getConnectRetryCount() >= 1, true);
    clientLastConnectTime = clientControlQueue.getLastConnectTime();
    expect(clientLastConnectTime > timeAfterSend, true);
    expect(clientLastConnectTime <= timeAfterTimeout, true);
    // The current packet_number of client side connection must be greater than that of previous one
    final sendPacketNumberAfterTimeout = clientConnection.sendPacketNumber;
    expect(sendPacketNumberAfterTimeout > initSendPacketNumber, true);

    // 7. Set client network environment to normal, and then wait for retry
    client.setNetworkEnv(NetworkEnvSimulator.acceptAll);
    bool connectedResult = await clientEstablished.future && await serverEstablished.future; // Wait for completions of both server side and client side

    // 8. Check status again
    expect(connectedResult, true);
    // The connection pool of client network_layer must have only 1 connection
    var clientConnections = client.connectionPool.getAllConnections();
    expect(clientConnections.length, 1);
    // Check network_layers' status
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);
    expect(sourceId != null, true);
    expect(destId != null, true);
    // Check client side connection's status
    expect(clientConnection.getSourceId(), sourceId);
    expect(clientConnection.getDestinationId(), destId);
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getStatus(), ConnectionStatus.established);
    // The retry queue of client side connection must be empty
    expect(clientConnection.retryQueue.messages.length, 0);
    // The current packet_number of client side connection must be greater than that of previous one
    expect(clientConnection.sendPacketNumber > sendPacketNumberAfterTimeout, true);
    // Check status of server side connection
    var serverConnection = server.connectionPool.getConnectionById(destId!);
    expect(serverConnection != null, true);
    expect(serverConnection!.getDestinationId(), sourceId);
    expect(serverConnection.getSourceId(), destId);
    expect(serverConnection.getStatus(), ConnectionStatus.established);

    // 9. Shutdown network services
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Network connect/connect_ack resend while client not receiving connect_ack', timeout: Timeout(Duration(seconds: 30)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    /// 1. Start network services server and client
    /// 2. Set server network environment to be "not sending connect_ack packet"
    /// 3. Connect to server
    /// 4. Check connection status
    /// 5. Wait for timeout
    /// 6. Check connection retry status
    /// 7. Set server network environment to normal, and then wait for retry
    /// 8. Check status again
    /// 9. Shutdown network services
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var serverEstablished = Completer<bool>();
    var lastClientPacketNumber = 0;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      deviceId: serverDeviceId,
      newConnectCallback: (c) {
        serverEstablished.complete(true);
      },
      onReceivePacket: (p) {
        final packetNumber = p.getPacketNumber();
        if(lastClientPacketNumber != 0) {
          // Make sure new arriving packet's packet_number is greater than that of previous one
          expect(packetNumber > lastClientPacketNumber, true);
        }
        lastClientPacketNumber = packetNumber;
        MyLogger.info('[Test] client packetNumber=$packetNumber');
      },
    );
    // Set server network environment to "not sending connect_ack message"
    server.setNetworkEnv(NetworkEnvSimulator(sendHook: (socket, ip, port, packet) {
      final type = packet.getType();
      if(type == PacketType.connectAck) {
        return 0;
      }
      return socket.send(packet.toBytes(), ip, port);
    }));
    MyLogger.info('[Test] start server');
    await server.start();

    var timeBeforeSend = DateTime.now().millisecondsSinceEpoch;
    int? sourceId, destId;
    var clientEstablished = Completer<bool>();
    var lastServerPacketNumber = 0;
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: 0,
      deviceId: clientDeviceId,
      connectOkCallback: (c) {
        sourceId = c.getSourceId();
        destId = c.getDestinationId();
        clientEstablished.complete(true);
      },
      onReceivePacket: (p) {
        MyLogger.info('[Test] receive packet');
        final packetNumber = p.getPacketNumber();
        if(lastServerPacketNumber != 0) {
          // Make sure new arriving packet's packet_number is greater than that of previous one
          expect(packetNumber > lastServerPacketNumber, true);
        }
        lastServerPacketNumber = packetNumber;
        MyLogger.info('[Test] server packetNumber=$packetNumber');
      },
    );
    MyLogger.info('[Test] start client');
    await client.start();
    client.connect(loopbackIp, serverPort);

    // Wait 1 second, and check connection pool
    await Future.delayed(Duration(milliseconds: 1000));
    var timeAfterSend = DateTime.now().millisecondsSinceEpoch;
    // Only 1 connection in client's pool, and destId must be 0, status is "initializing"
    var clientIncompleteConnections = client.incompletePool.getAllConnections();
    expect(clientIncompleteConnections.length, 1);
    var clientConnection = clientIncompleteConnections[0];
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getSourceId() != 0, true);
    expect(clientConnection.getDestinationId(), 0);
    expect(clientConnection.getStatus(), ConnectionStatus.establishing);
    // The control queue of client side connection must have exactly 1 connect packet, retry count is 0
    var clientControlQueue = clientConnection.controlQueue;
    var clientControlQueuePackets = clientControlQueue.getAllPackets();
    expect(clientControlQueuePackets.length, 1);
    expect(clientControlQueue.getConnectRetryCount(), 0);
    var clientLastConnectTime = clientControlQueue.getLastConnectTime();
    expect(clientLastConnectTime >= timeBeforeSend, true);
    expect(clientLastConnectTime < timeAfterSend, true);
    var msg = clientControlQueuePackets[0];
    expect(msg.getType(), PacketType.connect);

    // 5. Wait for timeout
    await Future.delayed(Duration(milliseconds: client.maxTimeout));
    var timeAfterTimeout = DateTime.now().millisecondsSinceEpoch;
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);

    // 6. Check connection retry status
    // The incomplete pool of server network_layer must have exactly 1 connection, and server connection status is "establishing"
    var serverIncompleteConnections = server.incompletePool.getAllConnections();
    expect(serverIncompleteConnections.length, 1);
    var serverConnection = serverIncompleteConnections[0];
    expect(serverConnection.getStatus(), ConnectionStatus.establishing);
    // The control queue of server network_layer must have exactly 1 element, which must be connect_ack
    var serverControlQueue = serverConnection.controlQueue;
    var serverControlQueuePackets = serverControlQueue.getAllPackets();
    expect(serverControlQueuePackets.length, 1);
    var serverLastConnectTime = serverControlQueue.getLastConnectTime();
    expect(serverLastConnectTime > timeAfterSend, true);
    expect(serverLastConnectTime <= timeAfterTimeout, true);
    var serverMsg = serverControlQueuePackets[0];
    expect(serverMsg.getType(), PacketType.connectAck);
    // The retry count of client side connection must be greater than or equal to 1
    clientLastConnectTime = clientControlQueue.getLastConnectTime();
    expect(clientControlQueue.getConnectRetryCount() >= 1, true);
    expect(clientLastConnectTime > timeAfterSend, true);
    expect(clientLastConnectTime <= timeAfterTimeout, true);

    // 7. Set server network environment to normal, and then wait for retry
    server.setNetworkEnv(NetworkEnvSimulator.acceptAll);
    bool connectedResult = await clientEstablished.future && await serverEstablished.future; // Wait for completions of both server side and client side

    // 8. Check status again
    expect(connectedResult, true);
    // The connection pool of client network_layer must have only 1 connection
    var clientConnections = client.connectionPool.getAllConnections();
    expect(clientConnections.length, 1);
    // Check network_layers' status
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);
    expect(sourceId != null, true);
    expect(destId != null, true);
    // Check client side connection's status
    expect(clientConnection.getSourceId(), sourceId);
    expect(clientConnection.getDestinationId(), destId);
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getStatus(), ConnectionStatus.established);
    // The retry queue of client side connection must be empty
    expect(clientConnection.retryQueue.messages.length, 0);
    // Check status of server side connection
    expect(serverConnection.getDestinationId(), sourceId);
    expect(serverConnection.getSourceId(), destId);
    expect(serverConnection.getStatus(), ConnectionStatus.established);

    // 9. Shutdown network services
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Network connect_ack resend while server not receiving connected', timeout: Timeout(Duration(seconds: 60)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    /// 1. Start network services server and client
    /// 2. Set client network environment to be "not sending connected packet"
    /// 3. Connect to server
    /// 4. Check connection status
    /// 5. Wait for timeout
    /// 6. Check connection retry status
    /// 7. Set client network environment to normal, and then wait for retry
    /// 8. Check status again
    /// 9. Shutdown network services
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var serverEstablished = Completer<bool>();
    var lastClientPacketNumber = 0;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      deviceId: serverDeviceId,
      newConnectCallback: (c) {
        serverEstablished.complete(true);
      },
      onReceivePacket: (p) {
        final packetNumber = p.getPacketNumber();
        if(lastClientPacketNumber != 0) {
          // Make sure new arriving packet's packet_number is greater than that of previous one
          expect(packetNumber > lastClientPacketNumber, true);
        }
        lastClientPacketNumber = packetNumber;
        MyLogger.info('[Test] client packetNumber=$packetNumber');
      },
    );
    await server.start();

    var timeBeforeSend = DateTime.now().millisecondsSinceEpoch;
    int? sourceId, destId;
    var clientEstablished = Completer<bool>();
    var lastServerPacketNumber = 0;
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: 0,
      deviceId: clientDeviceId,
      connectOkCallback: (c) {
        sourceId = c.getSourceId();
        destId = c.getDestinationId();
        clientEstablished.complete(true);
      },
      onReceivePacket: (p) {
        MyLogger.info('[Test] receive packet');
        final packetNumber = p.getPacketNumber();
        if(lastServerPacketNumber != 0) {
          // Make sure new arriving packet's packet_number is greater than that of previous one
          expect(packetNumber > lastServerPacketNumber, true);
        }
        lastServerPacketNumber = packetNumber;
        MyLogger.info('[Test] server packetNumber=$packetNumber');
      },
    );
    await client.start();
    // Set client network environment to be "not sending connected packet"
    client.setNetworkEnv(NetworkEnvSimulator(sendHook: (socket, ip, port, packet) {
      final type = packet.getType();
      if(type == PacketType.connected) {
        return 0;
      }
      return socket.send(packet.toBytes(), ip, port);
    }));
    client.connect(loopbackIp, serverPort);

    // Wait 1 second, and check connection pool
    await Future.delayed(Duration(milliseconds: 1000));
    var timeAfterSend = DateTime.now().millisecondsSinceEpoch;
    // Only 1 connection in client's pool, and destId is not 0, status is "established"
    var clientIncompleteConnections = client.incompletePool.getAllConnections();
    expect(clientIncompleteConnections.length, 0);
    var clientConnections = client.connectionPool.getAllConnections();
    expect(clientConnections.length, 1);
    var clientConnection = clientConnections[0];
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getSourceId() != 0, true);
    expect(clientConnection.getDestinationId() != 0, true);
    expect(clientConnection.getStatus(), ConnectionStatus.established);
    // Because connected packet will not retry, the control queue of client network_layer must be empty
    var clientControlQueue = clientConnection.controlQueue;
    var clientControlQueuePackets = clientControlQueue.getAllPackets();
    expect(clientControlQueuePackets.length, 0);
    // The incomplete pool of server network_layer must have exactly 1 connection, status is "establishing"
    var serverIncompleteConnections = server.incompletePool.getAllConnections();
    expect(serverIncompleteConnections.length, 1);
    var serverConnection = serverIncompleteConnections[0];
    expect(serverConnection.getStatus(), ConnectionStatus.establishing);
    // The control queue of server network_layer must have exactly 1 element, which must be connect_ack
    var serverControlQueue = serverConnection.controlQueue;
    var serverControlQueuePackets = serverControlQueue.getAllPackets();
    expect(serverControlQueuePackets.length, 1);
    var serverMsg = serverControlQueuePackets[0];
    expect(serverMsg.getType(), PacketType.connectAck);
    expect(serverControlQueue.getConnectRetryCount(), 0);
    var serverLastConnectTime = serverControlQueue.getLastConnectTime();
    expect(serverLastConnectTime >= timeBeforeSend, true);
    expect(serverLastConnectTime < timeAfterSend, true);

    // 5. Wait for timeout
    await Future.delayed(Duration(milliseconds: client.maxTimeout));
    var timeAfterTimeout = DateTime.now().millisecondsSinceEpoch;
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);

    // 6. Check connection retry status
    // The retry queue of server side connection must not be empty
    expect(serverControlQueue.getConnectRetryCount() >= 1, true);
    serverLastConnectTime = serverControlQueue.getLastConnectTime();
    expect(serverLastConnectTime > timeAfterSend, true);
    expect(serverLastConnectTime <= timeAfterTimeout, true);

    // 7. Set client network environment to normal, and then wait for retry
    client.setNetworkEnv(NetworkEnvSimulator.acceptAll);
    bool connectedResult = await clientEstablished.future && await serverEstablished.future; // Wait for completions of both server side and client side

    // 8. Check status again
    expect(connectedResult, true);
    // The connection pool of client network_layer must have only 1 connection
    expect(clientConnections.length, 1);
    // Check network_layers' status
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);
    expect(sourceId != null, true);
    expect(destId != null, true);
    // Check client network_layer's status
    expect(clientConnection.getSourceId(), sourceId);
    expect(clientConnection.getDestinationId(), destId);
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getStatus(), ConnectionStatus.established);
    // The retry queue of client side connection must be empty
    expect(clientConnection.retryQueue.messages.length, 0);
    // Check status of server side connection
    expect(serverConnection.getDestinationId(), sourceId);
    expect(serverConnection.getSourceId(), destId);
    expect(serverConnection.getStatus(), ConnectionStatus.established);

    // 9. Shutdown network services
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Network connect timeout and fail', timeout: Timeout(Duration(seconds: 30)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    /// 1. Start network services: server and client
    /// 2. Set server network environment as: drop all packets
    /// 3. Start a connection from client to server
    /// 4. Set connection's fail handler
    /// 5. Wait for timeout
    /// 6. Check connection status
    /// 7. Shutdown network services
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      deviceId: serverDeviceId,
    );
    await server.start();
    server.setNetworkEnv(NetworkEnvSimulator.dropAll);

    var clientFailed = Completer<bool>();
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: 0,
      deviceId: clientDeviceId,
    );
    await client.start();
    var connection = client.connect(loopbackIp, serverPort);
    expect(connection != null, true);
    connection!.onConnectionFail = (peer) {
      clientFailed.complete(true);
    };

    // Wait for complete
    await clientFailed.future;
    expect(connection.getStatus(), ConnectionStatus.invalid);

    // Shutdown network services
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Network connect shutdown', timeout: Timeout(Duration(seconds: 30)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    /// 1. Start network services: server and client
    /// 2. Connect to server
    /// 3. Close connection
    /// 4. Check connection status
    /// 5. Shutdown network services
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      deviceId: serverDeviceId,
    );
    await server.start();

    var clientClosed = Completer<bool>();
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: 0,
      deviceId: clientDeviceId,
    );
    await client.start();
    Peer? closedConnection;
    var connection = client.connect(loopbackIp, serverPort, onDisconnect: (peer) {
      closedConnection = peer;
      clientClosed.complete(true);
    });
    expect(connection != null, true);

    await Future.delayed(Duration(seconds: 5));
    connection!.close();
    // Wait for complete
    await clientClosed.future;
    expect(closedConnection, connection);
    expect(connection.getStatus(), ConnectionStatus.shutdown);

    // Shutdown network services
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Network connect automatically shutdown while server network_layer closed', timeout: Timeout(Duration(seconds: 30)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    /// 1. Start network services: server and client
    /// 2. Connect to server
    /// 3. Shutdown server network service
    /// 4. Check connection status
    /// 5. Shutdown client network service
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      deviceId: serverDeviceId,
    );
    await server.start();

    var clientClosed = Completer<bool>();
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: 0,
      deviceId: clientDeviceId,
    );
    await client.start();
    Peer? closedPeer;
    var clientPeer = client.connect(loopbackIp, serverPort, onDisconnect: (peer) {
      closedPeer = peer;
      clientClosed.complete(true);
    });
    expect(clientPeer != null, true);

    await Future.delayed(Duration(seconds: 5));
    server.stop();
    // Wait for complete
    await clientClosed.future;
    expect(closedPeer, clientPeer);
    expect(clientPeer!.getStatus(), ConnectionStatus.shutdown);

    // Shutdown network services
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Network connect automatically shutdown while client network_layer closed', timeout: Timeout(Duration(seconds: 30)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    /// 1. Start network services: server and client
    /// 2. Connect to server
    /// 3. Shutdown server network service
    /// 4. Check connection status
    /// 5. Shutdown client network service
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    Peer? serverPeer;
    Peer? closedPeer;
    var serverConnected = Completer<bool>();
    var serverClosed = Completer<bool>();
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      servicePort: serverPort,
      deviceId: serverDeviceId,
      newConnectCallback: (peer) {
        serverPeer = peer;
        serverPeer!.setOnDisconnect((p) {
          closedPeer = p;
          serverClosed.complete(true);
        });
        serverConnected.complete(true);
      }
    );
    await server.start();

    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      servicePort: 0,
      deviceId: clientDeviceId,
    );
    await client.start();
    var clientConnection = client.connect(loopbackIp, serverPort);
    expect(clientConnection != null, true);

    await serverConnected.future;
    await Future.delayed(Duration(seconds: 5));
    client.stop();
    // Wait for complete
    await serverClosed.future;
    expect(closedPeer, serverPeer);
    expect(clientConnection!.getStatus(), ConnectionStatus.shutdown);
    expect(serverPeer!.getStatus(), ConnectionStatus.shutdown);

    // Shutdown network services
    server.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });
}
