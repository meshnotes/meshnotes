import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:libp2p/network/incomplete_pool.dart';
import 'package:my_log/my_log.dart';
import 'package:libp2p/network/network_env.dart';
import 'package:libp2p/network/protocol/packet.dart';
import 'package:libp2p/utils.dart';
import 'peer.dart';
import 'protocol/util.dart';

enum NetworkStatus {
  invalid,
  running,
}

// Stateless Object Transfer Protocol
class SOTPNetworkLayer {
  static const multicastGroup = '224.0.0.179'; // Only 224.0.0.0/8 could be received by windows devices, by test result
  static const multicastGroup2 = '239.0.179.74'; // Try to send to other multicast address
  static const logPrefix = '[Network]';
  final connectionPool = ConnectionPool();
  final incompletePool = IncompletePool();
  late Timer timer;
  InternetAddress localIp;
  int servicePort;
  late int realPort;
  RawDatagramSocket? _udp;
  RawDatagramSocket get udp => _udp!;
  List<RawDatagramSocket> _broadcastSockets = [];
  NetworkStatus _status = NetworkStatus.invalid;
  NetworkStatus getStatus() => _status;
  int maxTimeout = 3000;
  NetworkEnvSimulator? _networkCondition;
  bool useMulticast;
  String _deviceId;
  int _lastSentMulticast = 0;
  static const _maxMulticastInterval = 20 * 1000; // 1 minute in milliseconds

  // Callback functions
  Function()? startedCallback; // Trigger after network layer started
  Function(Peer)? connectOkCallback; // Trigger after an outgoing connect is success, for client mode
  Function(Peer)? newConnectCallback; // Trigger after a new incoming connect is success, for server mode
  Function(Packet)? onReceivePacket; // Trigger after a packet is received
  Function(String, InternetAddress, int)? onDetected; // Trigger after a multicast announce message is received

  bool _debugIgnoreConnect = false;
  void setDebugIgnoreConnect(bool _b) => _debugIgnoreConnect = _b;
  bool _debugIgnoreConnectAck = false;
  void setDebugIgnoreConnectAck(bool _b) => _debugIgnoreConnectAck = _b;
  bool _debugIgnoreConnected = false;
  void setDebugIgnoreConnected(bool _b) => _debugIgnoreConnected = _b;
  bool _debugIgnoreData = false;
  void setDebugIgnoreData(bool _b) => _debugIgnoreData = _b;

  SOTPNetworkLayer({
    required this.localIp,
    required this.servicePort,
    this.connectOkCallback,
    this.newConnectCallback,
    this.onReceivePacket,
    this.onDetected,
    NetworkEnvSimulator? networkCondition,
    this.useMulticast = false,
    required String deviceId,
  }) : _networkCondition = networkCondition, _deviceId = deviceId;

  start() async {
    _udp = await RawDatagramSocket.bind(localIp, servicePort);
    realPort = udp.port;
    _status = NetworkStatus.running;
    udp.listen((event) {
      if(event == RawSocketEvent.read) {
        var receivedData = udp.receive()!;
        var data = receivedData.data;
        var peerIp = receivedData.address;
        var port = receivedData.port;

        MyLogger.verbose('${logPrefix} Receive data: ${data}');
        var packetFactory = PacketFactory(data: data);
        final type = packetFactory.getType();
        if(type == PacketType.invalid) {
          MyLogger.warn('${logPrefix} Receive invalid packet: $data');
          return;
        }
        var packet = packetFactory.getAbstractPacket()!;
        MyLogger.debug('${logPrefix} Receive packet with type(${packet.getType().name})');
        onReceivePacket?.call(packet);
        switch(type) {
          case PacketType.connect:
            if(_debugIgnoreConnect) break;
            _onConnect(peerIp, port, packet as PacketConnect);
            break;
          case PacketType.connectAck:
            if(_debugIgnoreConnectAck) break;
            _onConnectAck(peerIp, port, packet as PacketConnect);
            break;
          case PacketType.connected:
            if(_debugIgnoreConnected) break;
            _onConnected(peerIp, port, packet as PacketConnect);
            break;
          case PacketType.data:
            if(_debugIgnoreData) break;
            _onData(packet as PacketData);
            break;
          case PacketType.announce:
            if(peerIp == localIp && port == servicePort) break; // Ignore packet from itself
            _onAnnounce(packet as PacketAnnounce, peerIp, port);
            break;
          case PacketType.announceAck:
            if(!useMulticast) break; // Ignore announce_ack if not supporting multicast
            if(peerIp == localIp && port == servicePort) break; // Ignore packet from itself
            _onAnnounceAck(packet as PacketAnnounce, peerIp, port);
            break;
          case PacketType.bye:
            _onBye(packet as PacketBye);
            break;
          case PacketType.invalid: // Not possible
            break;
        }
      }
    });
    if (useMulticast) {
      _udp?.joinMulticast(InternetAddress(multicastGroup));
      _udp?.joinMulticast(InternetAddress(multicastGroup2));
      _startBroadcast(); // Bind every interface with random port, to send multicast message
    }
    timer = Timer.periodic(Duration(milliseconds: 1000), _networkTimerHandler);
    startedCallback?.call();
  }

  void setNetworkEnv(NetworkEnvSimulator? _env) {
    _networkCondition = _env;
  }

  stop() {
    MyLogger.info('${logPrefix} Shutdown network_layer');
    if(_status == NetworkStatus.invalid) return;
    timer.cancel();
    _traverseAndClose(connectionPool.getAllConnections());
    _traverseAndClose(incompletePool.getAllConnections());
    udp.close();
    _status = NetworkStatus.invalid;
  }

  Peer connect(String peerIp, int peerPort, {OnReceiveDataCallback? onReceive = null, OnDisconnectCallback? onDisconnect, OnConnectionFail? onConnectionFail, }) {
    // 1. 生成source connection Id
    // 2. 将connection置为initializing状态
    // 3. 发送connect消息
    var id = _generateId();
    var ip = InternetAddress(peerIp);
    var peer = Peer(ip: ip, port: peerPort, transport: _sendDelegate, onReceiveData: onReceive, onDisconnect: onDisconnect, onConnectionFail: onConnectionFail)
      ..setInitializing()
      ..setSourceId(id);
    MyLogger.info('${logPrefix} Connecting ip=$peerIp, port=$peerPort, id=$id');
    incompletePool.addConnection(ip, peerPort, id, peer);
    peer.connect();
    return peer;
  }
  void _onConnect(InternetAddress peerIp, int peerPort, PacketConnect packet) {
    // 1. 收到connect消息后，先判断是否已有Peer（有可能是重发的connect消息）。如果没有，则生成新的Peer，生成source connection Id
    // 2. 因为方向是相反的，将报文的source connection Id设置为dest connection Id
    // 3. 将peer状态置为establishing
    // 4. 发送connect_ack

    // 假设客户端还未收到connect_ack，因此客户端还不知道服务端的connection_id，因此只能用客户端的connection_id来判断连接
    var originalId = packet.sourceConnectionId;
    var peer = incompletePool.getConnection(peerIp, peerPort, originalId);
    if(peer == null) {
      peer = Peer(ip: peerIp, port: peerPort, transport: _sendDelegate)
        ..setEstablishing();
      peer.setSourceId(_generateId());
      peer.setDestinationId(originalId);
      incompletePool.addConnection(peerIp, peerPort, originalId, peer);
    }
    peer.onConnect(packet);
  }
  void _onConnectAck(InternetAddress ip, int port, PacketConnect packet) {
    // 1. 只有客户端才会收到connect_ack，因此根据消息包的ip、端口、source connection Id查找connection
    // 2. 如果在incompletePool查不到connection，有可能是connected消息丢失，从connectionPool查找
    // 3. 发送connected消息
    // 4. 连接已建立，将connection从incompletePool转移到connectionPool
    var originalId = packet.header.destConnectionId;
    var peer = incompletePool.getConnection(ip, port, originalId);
    var fromIncomplete = peer != null;
    if(peer == null) {
      peer = connectionPool.getConnectionById(originalId);
      if(peer == null) { // 如果还找不到，则不处理
        MyLogger.warn('${logPrefix}Connection not found on receiving connect_ack: ip=$ip, port=$port, destConnectionId=$originalId');
        return;
      }
    }
    if(peer.onConnectAck(packet) && fromIncomplete) {
      incompletePool.removeConnection(ip, port, originalId);
      connectionPool.addConnection(peer);
      connectOkCallback?.call(peer);
    }
  }
  void _onConnected(InternetAddress ip, int port, PacketConnect packet) {
    // 1. 如果是首次收到connected消息，要从incompletePool取得connection。如果是重发的connected消息，要从connectionPool取得connection
    // 2. 交给connection处理
    var originalId = packet.sourceConnectionId;
    var peer = incompletePool.getConnection(ip, port, originalId);
    if(peer == null) { // 如果incompletePool没有找到，可能是重发的connected，改为从connectionPool寻找
      peer = connectionPool.getConnectionById(packet.header.destConnectionId);
      if(peer == null) {
        MyLogger.warn('${logPrefix}Connection not found on receiving connected: ip=$ip, port=$port, sourceConnectionId=$originalId');
        return;
      }
    }
    if(peer.onConnected(packet)) {
      incompletePool.removeConnection(ip, port, originalId);
      connectionPool.addConnection(peer);
      newConnectCallback?.call(peer);
    }
  }
  void _onData(PacketData packet) {
    final header = packet.header;
    var peer = _getConnectionFromHeader(header);
    if(peer == null) return;

    peer.onData(packet);
  }
  void _onAnnounce(PacketAnnounce packet, InternetAddress ip, int port) {
    String peerDeviceId = packet.deviceId;
    String peerIp = buildIpAddress(packet.address);
    int peerPort = packet.port;
    if(peerDeviceId == _deviceId) return;
    MyLogger.info('${logPrefix} receive announce message from ${ip.address}:$port, with peerIP($peerIp):peerPort($peerPort), deviceId($peerDeviceId), my deviceId(${_deviceId})');
    _sendAnnounceAck(ip, peerPort);
    onDetected?.call(peerDeviceId, ip, peerPort); // announce message is sent from broadcast socket, so use peerPort to contact to peer
  }
  void _onAnnounceAck(PacketAnnounce packet, InternetAddress ip, int port) {
    String peerDeviceId = packet.deviceId;
    String peerIp = buildIpAddress(packet.address);
    int peerPort = packet.port;
    if(peerDeviceId == _deviceId) return; // Impossible
    MyLogger.debug('${logPrefix} receive announce_ack message from ${ip.address}:$port, with peerIP($peerIp):peerPort($peerPort), deviceId($peerDeviceId)');
    onDetected?.call(peerDeviceId, ip, port); // Unlike _onAnnounce, announce_ack is sent from service socket, so use port directly
  }

  void _sendAnnounce(RawDatagramSocket socket, InternetAddress targetAddress, int targetPort, Uint8List myAddress, int myPort) {
    int intAddress = myAddress.buffer.asByteData().getInt32(0);
    PacketAnnounce reply = PacketAnnounce(
      deviceId: _deviceId,
      address: intAddress,
      port: myPort,
      header: PacketHeader(type: PacketType.announce, destConnectionId: 0, packetNumber: 0),
    );
    _sendDelegate(reply.toBytes(), targetAddress, targetPort, socket: socket);
  }
  void _sendAnnounceAck(InternetAddress ip, int port) {
    PacketAnnounce reply = PacketAnnounce(
      deviceId: _deviceId,
      address: 0,
      port: servicePort,
      header: PacketHeader(type: PacketType.announceAck, destConnectionId: 0, packetNumber: 0),
    );
    _sendDelegate(reply.toBytes(), ip, port);
  }

  void _onBye(PacketBye packet) {
    final header = packet.header;
    if(packet.tag == PacketBye.tagByeAck) { // Receive bye_ack, ignore it
      return;
    }
    var peer = _getConnectionFromHeader(header);
    if(peer == null) return;

    peer.onClose();
  }
  Peer? _getConnectionFromHeader(PacketHeader header) {
    var peer = connectionPool.getConnectionById(header.destConnectionId);
    if(peer?.getStatus() != ConnectionStatus.established) {
      return null;
    }
    return peer;
  }

  void _startBroadcast() async {
    List<NetworkInterface> interfaces = await NetworkInterface.list();
    
    for(var interface in interfaces) {
      for(var addr in interface.addresses) {
        try {
          var socket = await RawDatagramSocket.bind(addr, 0);
          socket.joinMulticast(InternetAddress(multicastGroup));
          socket.joinMulticast(InternetAddress(multicastGroup2));
          socket.multicastLoopback = false;
          _broadcastSockets.add(socket);

          MyLogger.info('${logPrefix} Bind broadcast socket to ${addr.address}:${socket.port}');
        } catch(e) {
          MyLogger.warn('${logPrefix} Failed to bind broadcast socket to ${addr.address}: $e');
          continue;
        }
      }
    }
  }

  int _generateId() {
    while(true) {
      int id = randomId();
      // FIXME May duplicated with incompletePool's id
      if(connectionPool.getConnectionById(id) == null) {
        return id;
      }
    }
  }

  int _sendDelegate(List<int> data, InternetAddress ip, int port, {RawDatagramSocket? socket = null}) {
    if(socket == null) socket = udp;
    var sendData = _networkCondition?.sendHook?.call(data)?? true;
    if(sendData) {
      return socket.send(data, ip, port);
    } else {
      return 0;
    }
  }

  void _networkTimerHandler(Timer _t) {
    /// 1. Resend connections and incomplete connections
    /// 2. Clear invalid or disconnected connections
    /// 3. Broadcast announce
    int now = DateTime.now().millisecondsSinceEpoch;
    _traverseAndResend(connectionPool.getAllConnections(), now);
    _traverseAndResend(incompletePool.getAllConnections(), now);
    _clearInvalidConnections();
    if(useMulticast) {
      _tryMulticast(now);
    }
  }
  void _traverseAndResend(Iterable<Peer> connections, int now) {
    var timestamp = now - maxTimeout;
    for(var conn in connections) {
      conn.updateResendQueue(timestamp);
      conn.updateControlQueue(timestamp);
    }
  }
  void _clearInvalidConnections() {
    var _ = connectionPool.removeInvalidAndClosedConnections();
    _ = incompletePool.removeInvalidAndClosedConnections();
  }
  void _traverseAndClose(List<Peer> connections) {
    for(var conn in connections) {
      conn.close();
    }
  }
  void _tryMulticast(int now) {
    if(now - _lastSentMulticast > _maxMulticastInterval) {
      MyLogger.debug('${logPrefix} Send multicast message to $multicastGroup and $multicastGroup2');
      for(var socket in _broadcastSockets) {
        _tryMulticastForEveryInterface(now, socket);
      }
      _lastSentMulticast = now;
    }
  }
  void _tryMulticastForEveryInterface(int now, RawDatagramSocket socket) {
    MyLogger.debug('${logPrefix} Send multicast message from ${socket.address.address}:${socket.port}');
    // Use service port as both the localPort and target port
    // _sendAnnounce(socket, InternetAddress(multicastGroup), servicePort, socket.address.rawAddress, servicePort);
    _sendAnnounce(socket, InternetAddress(multicastGroup), servicePort, InternetAddress(multicastGroup).rawAddress, servicePort);
    _sendAnnounce(socket, InternetAddress(multicastGroup2), servicePort, InternetAddress(multicastGroup2).rawAddress, servicePort);
  }
}