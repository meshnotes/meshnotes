import 'dart:async';
import 'dart:io';

import 'package:libp2p/network/peer.dart';
import 'package:my_log/my_log.dart';
import 'package:libp2p/network/network_env.dart';
import 'package:libp2p/network/packet/packet.dart';
import 'package:test/test.dart';
import 'package:libp2p/network/network_layer.dart';

void main() {
  var serverPort = 8081;
  test('Network connection', timeout: Timeout(Duration(seconds: 5)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    // 1. 启动网络服务server和client
    // 2. 建立client到server的连接
    // 3. 检查连接状态、Id，检查packet_number
    // 4. 检查发送队列，没有待重发的消息
    // 5. 关闭服务
    // 6. 再次检查状态
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var serverEstablished = Completer<bool>();
    var lastClientPacketNumber = 0;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      localPort: serverPort,
      newConnectCallback: (c) {
        serverEstablished.complete(true);
      },
      onReceivePacket: (p) {
        final packetNumber = p.getPacketNumber();
        if(lastClientPacketNumber != 0) {
          // 确保新收到的packet_number必然等于上一个packet_number+1
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
      localPort: 0,
      connectOkCallback: (c) {
        sourceId = c.getSourceId();
        destId = c.getDestinationId();
        clientEstablished.complete(true);
      },
      onReceivePacket: (p) {
        final packetNumber = p.getPacketNumber();
        if(lastServerPacketNumber != 0) {
          // 确保新收到的packet_number必然等于上一个packet_number+1
          expect(packetNumber, lastServerPacketNumber + 1);
        }
        lastServerPacketNumber = packetNumber;
        MyLogger.info('[Test] server packetNumber=$packetNumber');
      },
    );
    await client.start();
    client.connect(loopbackIp, serverPort);
    bool connectedResult = await clientEstablished.future && await serverEstablished.future; // 必须等客户端和服务端都完成，否则状态可能不正确

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

    // 4. 检查发送队列，没有待重发的消息
    expect(serverConnection.retryQueue.messages.length, 0);
    expect(clientConnection.retryQueue.messages.length, 0);

    // 5. 关闭服务
    server.stop();
    client.stop();
    // 6. 再次检查状态
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Network connect resend while server not receiving connect', timeout: Timeout(Duration(seconds: 30)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    // 1. 启动网络服务server和client
    // 2. 设置client网络为：丢弃所有消息
    // 3. 建立client到server的连接
    // 4. 检查连接状态、Id、packet_number
    // 5. 等待超时
    // 6. 检查重发的状态、packet_number
    // 7. 将client网络环境恢复正常，等待重连
    // 8. 重新检查状态、packet_number
    // 9. 关闭服务
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var serverEstablished = Completer<bool>();
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      localPort: serverPort, newConnectCallback: (c) {
        serverEstablished.complete(true);
      },
    );
    await server.start();

    var timeBeforeSend = DateTime.now().millisecondsSinceEpoch;
    int? sourceId, destId;
    var clientEstablished = Completer<bool>();
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      localPort: 0,
      connectOkCallback: (c) {
        sourceId = c.getSourceId();
        destId = c.getDestinationId();
        clientEstablished.complete(true);
      },
    );
    await client.start();
    client.setNetworkEnv(NetworkEnvSimulator.dropAll);
    client.connect(loopbackIp, serverPort);

    // 等待1秒，检查发送队列
    await Future.delayed(Duration(milliseconds: 1000));
    var timeAfterSend = DateTime.now().millisecondsSinceEpoch;
    // Client必然只有一个连接，且destId未完成，状态为initializing
    var clientIncompleteConnections = client.incompletePool.getAllConnections();
    expect(clientIncompleteConnections.length, 1);
    var clientConnection = clientIncompleteConnections[0];
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getSourceId() != 0, true);
    expect(clientConnection.getDestinationId(), 0);
    expect(clientConnection.getStatus(), ConnectionStatus.initializing);
    // Client控制队列必然有类型为connect的消息，重试次数为0，记录下sendPacketNumber
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

    // 5. 等待到超时
    await Future.delayed(Duration(milliseconds: client.maxTimeout));
    var timeAfterTimeout = DateTime.now().millisecondsSinceEpoch;
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);

    // 6. 检查重发状态
    // Server必然无连接
    var serverIncompleteConnections = server.incompletePool.getAllConnections();
    expect(serverIncompleteConnections.length, 0);
    // 此时控制队列的连接重试次数应该>=1
    expect(clientControlQueue.getConnectRetryCount() >= 1, true);
    clientLastConnectTime = clientControlQueue.getLastConnectTime();
    expect(clientLastConnectTime > timeAfterSend, true);
    expect(clientLastConnectTime <= timeAfterTimeout, true);
    // 此时的sendPacketNumber必然增大
    final sendPacketNumberAfterTimeout = clientConnection.sendPacketNumber;
    expect(sendPacketNumberAfterTimeout > initSendPacketNumber, true);

    // 7. 将client网络环境恢复正常，等待重连
    client.setNetworkEnv(NetworkEnvSimulator.acceptAll);
    bool connectedResult = await clientEstablished.future && await serverEstablished.future; // 必须等客户端和服务端都完成，否则状态可能不正确

    // 8. 重新检查状态
    expect(connectedResult, true);
    // 连接池中仍然只有一个连接
    var clientConnections = client.connectionPool.getAllConnections();
    expect(clientConnections.length, 1);
    // 检查服务状态
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);
    expect(sourceId != null, true);
    expect(destId != null, true);
    // 检查客户端连接状态
    expect(clientConnection.getSourceId(), sourceId);
    expect(clientConnection.getDestinationId(), destId);
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getStatus(), ConnectionStatus.established);
    // 检查客户端发送队列是否为空
    expect(clientConnection.retryQueue.messages.length, 0);
    // 客户端sendPacketNumber必然大于超时连接失败时的sendPacketNumber
    expect(clientConnection.sendPacketNumber > sendPacketNumberAfterTimeout, true);
    // 检查服务端连接状态
    var serverConnection = server.connectionPool.getConnectionById(destId!);
    expect(serverConnection != null, true);
    expect(serverConnection!.getDestinationId(), sourceId);
    expect(serverConnection.getSourceId(), destId);
    expect(serverConnection.getStatus(), ConnectionStatus.established);

    // 9. 关闭服务
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Network connect/connect_ack resend while client not receiving connect_ack', timeout: Timeout(Duration(seconds: 30)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    // 1. 启动网络服务server和client
    // 2. 设置server的网络环境为：不处理connect_ack消息
    // 3. 建立client到server的连接
    // 4. 检查连接状态、Id
    // 5. 等待超时
    // 6. 检查重发的状态
    // 7. 将server网络环境恢复正常，等待重连
    // 8. 重新检查状态
    // 9. 关闭服务
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var serverEstablished = Completer<bool>();
    var lastClientPacketNumber = 0;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      localPort: serverPort,
      newConnectCallback: (c) {
        serverEstablished.complete(true);
      },
      onReceivePacket: (p) {
        final packetNumber = p.getPacketNumber();
        if(lastClientPacketNumber != 0) {
          // 确保新收到的packet_number必然比上一个packet_number要大，由于可能超时，这里不严格判断比上一个packet_number大1
          expect(packetNumber > lastClientPacketNumber, true);
        }
        lastClientPacketNumber = packetNumber;
        MyLogger.info('[Test] client packetNumber=$packetNumber');
      },
    );
    // Set server network environment to "not sending connect_ack message"
    server.setNetworkEnv(NetworkEnvSimulator()..sendHook = (data) {
      var factory = PacketFactory(data: data);
      final type = factory.getType();
      if(type == PacketType.connectAck) {
        return false;
      }
      return true;
    });
    MyLogger.info('[Test] start server');
    await server.start();

    var timeBeforeSend = DateTime.now().millisecondsSinceEpoch;
    int? sourceId, destId;
    var clientEstablished = Completer<bool>();
    var lastServerPacketNumber = 0;
    var client = SOTPNetworkLayer(
      localIp: InternetAddress(loopbackIp),
      localPort: 0,
      connectOkCallback: (c) {
        sourceId = c.getSourceId();
        destId = c.getDestinationId();
        clientEstablished.complete(true);
      },
      onReceivePacket: (p) {
        MyLogger.info('[Test] receive packet');
        final packetNumber = p.getPacketNumber();
        if(lastServerPacketNumber != 0) {
          // 确保新收到的packet_number必然比上一个packet_number要大，由于可能超时，这里不严格判断比上一个packet_number大1
          expect(packetNumber > lastServerPacketNumber, true);
        }
        lastServerPacketNumber = packetNumber;
        MyLogger.info('[Test] server packetNumber=$packetNumber');
      },
    );
    MyLogger.info('[Test] start client');
    await client.start();
    client.connect(loopbackIp, serverPort);

    // 等待1秒，检查发送队列
    await Future.delayed(Duration(milliseconds: 1000));
    var timeAfterSend = DateTime.now().millisecondsSinceEpoch;
    // Client必然只有一个连接，且destId未完成，状态为initializing
    var clientIncompleteConnections = client.incompletePool.getAllConnections();
    expect(clientIncompleteConnections.length, 1);
    var clientConnection = clientIncompleteConnections[0];
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getSourceId() != 0, true);
    expect(clientConnection.getDestinationId(), 0);
    expect(clientConnection.getStatus(), ConnectionStatus.initializing);
    // Client控制队列必然有类型为connect的消息，重试次数为0，记录下sendPacketNumber
    var clientControlQueue = clientConnection.controlQueue;
    var clientControlQueuePackets = clientControlQueue.getAllPackets();
    expect(clientControlQueuePackets.length, 1);
    expect(clientControlQueue.getConnectRetryCount(), 0);
    var clientLastConnectTime = clientControlQueue.getLastConnectTime();
    expect(clientLastConnectTime >= timeBeforeSend, true);
    expect(clientLastConnectTime < timeAfterSend, true);
    var msg = clientControlQueuePackets[0];
    expect(msg.getType(), PacketType.connect);

    // 5. 等待到超时
    await Future.delayed(Duration(milliseconds: client.maxTimeout));
    var timeAfterTimeout = DateTime.now().millisecondsSinceEpoch;
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);

    // 6. 检查重发状态
    // Server必然有1个连接
    var serverIncompleteConnections = server.incompletePool.getAllConnections();
    expect(serverIncompleteConnections.length, 1);
    var serverConnection = serverIncompleteConnections[0];
    expect(serverConnection.getStatus(), ConnectionStatus.establishing);
    // Server控制队列必然有类型为connect_ack的消息，重试次数重试次数>=1
    var serverControlQueue = serverConnection.controlQueue;
    var serverControlQueuePackets = serverControlQueue.getAllPackets();
    expect(serverControlQueuePackets.length, 1);
    var serverLastConnectTime = serverControlQueue.getLastConnectTime();
    expect(serverLastConnectTime > timeAfterSend, true);
    expect(serverLastConnectTime <= timeAfterTimeout, true);
    var serverMsg = serverControlQueuePackets[0];
    expect(serverMsg.getType(), PacketType.connectAck);
    // 此时客户端发送队列的消息重试次数应该>=1
    clientLastConnectTime = clientControlQueue.getLastConnectTime();
    expect(clientControlQueue.getConnectRetryCount() >= 1, true);
    expect(clientLastConnectTime > timeAfterSend, true);
    expect(clientLastConnectTime <= timeAfterTimeout, true);

    // 7. 将server网络环境恢复正常，等待重连
    server.setNetworkEnv(NetworkEnvSimulator.acceptAll);
    bool connectedResult = await clientEstablished.future && await serverEstablished.future; // 必须等客户端和服务端都完成，否则状态可能不正确

    // 8. 重新检查状态
    expect(connectedResult, true);
    // 连接池中仍然只有一个连接
    var clientConnections = client.connectionPool.getAllConnections();
    expect(clientConnections.length, 1);
    // 检查服务状态
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);
    expect(sourceId != null, true);
    expect(destId != null, true);
    // 检查客户端连接状态
    expect(clientConnection.getSourceId(), sourceId);
    expect(clientConnection.getDestinationId(), destId);
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getStatus(), ConnectionStatus.established);
    // 检查客户端发送队列是否为空
    expect(clientConnection.retryQueue.messages.length, 0);
    // 检查服务端连接状态
    expect(serverConnection.getDestinationId(), sourceId);
    expect(serverConnection.getSourceId(), destId);
    expect(serverConnection.getStatus(), ConnectionStatus.established);

    // 9. 关闭服务
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });

  test('Network connect_ack resend while server not receiving connected', timeout: Timeout(Duration(seconds: 60)), () async {
    MyLogger.initForTest(name: 'libp2p_test');
    // 1. 启动网络服务server和client
    // 2. 设置client网络环境为：不处理connected消息
    // 3. 建立client到server的连接
    // 4. 检查连接状态、Id
    // 5. 等待超时
    // 6. 检查重发的状态
    // 7. 将client网络环境恢复正常，等待重连
    // 8. 重新检查状态
    // 9. 关闭服务
    var serverIp = InternetAddress.anyIPv4;
    var loopbackIp = "127.0.0.1";
    var serverEstablished = Completer<bool>();
    var lastClientPacketNumber = 0;
    var server = SOTPNetworkLayer(
      localIp: serverIp,
      localPort: serverPort,
      newConnectCallback: (c) {
        serverEstablished.complete(true);
      },
      onReceivePacket: (p) {
        final packetNumber = p.getPacketNumber();
        if(lastClientPacketNumber != 0) {
          // 确保新收到的packet_number必然比上一个packet_number要大，由于可能超时，这里不严格判断比上一个packet_number大1
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
      localPort: 0,
      connectOkCallback: (c) {
        sourceId = c.getSourceId();
        destId = c.getDestinationId();
        clientEstablished.complete(true);
      },
      onReceivePacket: (p) {
        MyLogger.info('[Test] receive packet');
        final packetNumber = p.getPacketNumber();
        if(lastServerPacketNumber != 0) {
          // 确保新收到的packet_number必然比上一个packet_number要大，由于可能超时，这里不严格判断比上一个packet_number大1
          expect(packetNumber > lastServerPacketNumber, true);
        }
        lastServerPacketNumber = packetNumber;
        MyLogger.info('[Test] server packetNumber=$packetNumber');
      },
    );
    await client.start();
    // Set client network environment to be "not sending connected message"
    client.setNetworkEnv(NetworkEnvSimulator()..sendHook = (data) {
      var factory = PacketFactory(data: data);
      final type = factory.getType();
      if(type == PacketType.connected) {
        return false;
      }
      return true;
    });
    client.connect(loopbackIp, serverPort);

    // 等待1秒，检查发送队列
    await Future.delayed(Duration(milliseconds: 1000));
    var timeAfterSend = DateTime.now().millisecondsSinceEpoch;
    // Client必然只有一个连接，且destId未完成，状态为initializing
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
    // 因为connected不是重发消息，Client控制队列必然无元素
    var clientControlQueue = clientConnection.controlQueue;
    var clientControlQueuePackets = clientControlQueue.getAllPackets();
    expect(clientControlQueuePackets.length, 0);
    // Server的Incomplete池必然有一个连接
    var serverIncompleteConnections = server.incompletePool.getAllConnections();
    expect(serverIncompleteConnections.length, 1);
    var serverConnection = serverIncompleteConnections[0];
    // Server的控制队列必然有1个元素，消息类型为connect_ack
    var serverControlQueue = serverConnection.controlQueue;
    var serverControlQueuePackets = serverControlQueue.getAllPackets();
    expect(serverControlQueuePackets.length, 1);
    var serverMsg = serverControlQueuePackets[0];
    expect(serverMsg.getType(), PacketType.connectAck);
    expect(serverControlQueue.getConnectRetryCount(), 0);
    var serverLastConnectTime = serverControlQueue.getLastConnectTime();
    expect(serverLastConnectTime >= timeBeforeSend, true);
    expect(serverLastConnectTime < timeAfterSend, true);

    // 5. 等待到超时
    await Future.delayed(Duration(milliseconds: client.maxTimeout));
    var timeAfterTimeout = DateTime.now().millisecondsSinceEpoch;
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);

    // 6. 检查重发状态
    // 此时发送队列的消息重试次数应该>=1
    expect(serverControlQueue.getConnectRetryCount() >= 1, true);
    serverLastConnectTime = serverControlQueue.getLastConnectTime();
    expect(serverLastConnectTime > timeAfterSend, true);
    expect(serverLastConnectTime <= timeAfterTimeout, true);

    // 7. 将client网络环境恢复正常，等待重连
    // server.setDebugIgnoreConnected(false);
    client.setNetworkEnv(NetworkEnvSimulator.acceptAll);
    bool connectedResult = await clientEstablished.future && await serverEstablished.future; // 必须等客户端和服务端都完成，否则状态可能不正确

    // 8. 重新检查状态
    expect(connectedResult, true);
    // Client的连接池中仍然只有一个连接
    expect(clientConnections.length, 1);
    // 检查服务状态
    expect(server.getStatus(), NetworkStatus.running);
    expect(client.getStatus(), NetworkStatus.running);
    expect(sourceId != null, true);
    expect(destId != null, true);
    // 检查客户端连接状态
    expect(clientConnection.getSourceId(), sourceId);
    expect(clientConnection.getDestinationId(), destId);
    expect(clientConnection.ip, InternetAddress(loopbackIp));
    expect(clientConnection.port, serverPort);
    expect(clientConnection.getStatus(), ConnectionStatus.established);
    // 检查客户端发送队列是否为空
    expect(clientConnection.retryQueue.messages.length, 0);
    // 检查服务端连接状态
    expect(serverConnection.getDestinationId(), sourceId);
    expect(serverConnection.getSourceId(), destId);
    expect(serverConnection.getStatus(), ConnectionStatus.established);

    // 9. 关闭服务
    server.stop();
    client.stop();
    expect(server.getStatus(), NetworkStatus.invalid);
    expect(client.getStatus(), NetworkStatus.invalid);
  });
}
