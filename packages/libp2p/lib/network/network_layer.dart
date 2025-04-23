import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:bonsoir/bonsoir.dart';
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
  static const _bonjourName = 'VillageProtocol';
  static const _bonjourType = '_village-v0._udp';
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
  bool useBonjour;
  BonsoirBroadcast? _bonjourBroadcast;
  BonsoirDiscovery? _bonjourDiscovery;
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
    this.useBonjour = false, // Ignore bonjour, because it could not be used in background isolates
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
            if(!useMulticast && !useBonjour) break; // Ignore announce_ack if not supporting multicast or bonjour
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
    if(useMulticast) {
      _udp?.joinMulticast(InternetAddress(multicastGroup));
      _udp?.joinMulticast(InternetAddress(multicastGroup2));
      _startBroadcast(); // Bind every interface with random port, to send multicast message
    }
    if(useBonjour) {
      _startBonjour();
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
    if(useBonjour) {
      _bonjourBroadcast?.stop();
      _bonjourDiscovery?.stop();
    }
    udp.close();
    _status = NetworkStatus.invalid;
  }

  Peer? connect(String peerIp, int peerPort, {OnReceiveDataCallback? onReceive = null, OnDisconnectCallback? onDisconnect, OnConnectionFail? onConnectionFail, }) {
    // 1. Generate source connection Id randomly
    // 2. Set connection status to initializing
    // 3. Send connect message
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
    // 1. When received connect message, find if peer is already exists(may be duplicated connect message). If not, generate a new one with source_connection_id
    // 2. Exchange the source/destination id from receiving packet
    // 3. Set peer's connection status to establishing
    // 4. Send connect_ack

    // When received connect, client side didn't know the server side connection_id(which will be send in server's connect_ack)
    // So search ip:port:source_connection_id in incompletePool
    // After connection is established, will use ip:port:dest_connection_id to find connection
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
    // 1. Only client will receive connect_ack, so find connection by ip, port, and source_connection_id
    // 2. If connection is not found in incompletePool, may cause by lost connected message(so server side resend connect_ack), search again in connectionPool
    // 3. Send connected message
    // 4. Now connection is successfully established, move it from incompletePool to connectionPool

    var originalId = packet.header.destConnectionId;
    var peer = incompletePool.getConnection(ip, port, originalId);
    var fromIncomplete = peer != null;
    if(peer == null) {
      peer = connectionPool.getConnectionById(originalId);
      if(peer == null) { // Ignore it if connection not found
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
    // 1. If it's the first time to receive connected, should retrieve peer from incompletePool.
    //    If connected is duplicated, should retrieve peer from connectionPool
    // 2. Let peer to handle connected message
    // 3. If connection is successfully established for the first time, trigger callback and move it from incompletePool to connectionPool
    var originalId = packet.sourceConnectionId;
    var peer = incompletePool.getConnection(ip, port, originalId);
    // If connection not found in incompletePool, may cause by lost connected message(so server side resend connect_ack), search again in connectionPool
    if(peer == null) {
      peer = connectionPool.getConnectionById(packet.header.destConnectionId);
      if(peer == null) {
        MyLogger.warn('${logPrefix}Connection not found on receiving connected: ip=$ip, port=$port, sourceConnectionId=$originalId');
        return;
      }
    }
    if(peer.onConnected(packet)) { // If peer is already established, here will return false
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
  Future<void> _startBonjour() async {
    _startBonjourBroadcast();
    _startBonjourDiscovery();
  }
  Future<void> _startBonjourBroadcast() async {
    BonsoirService service = BonsoirService(
      name: _bonjourName,

      type: _bonjourType,
      port: servicePort, // Put your service port here.
      attributes: {
        'device': _deviceId,
      },
    );

    // And now we can broadcast it :
    BonsoirBroadcast broadcast = BonsoirBroadcast(service: service);
    await broadcast.ready;
    await broadcast.start();
    _bonjourBroadcast = broadcast;
  }
  Future<void> _startBonjourDiscovery() async {
    BonsoirDiscovery discovery = BonsoirDiscovery(type: _bonjourType);
    await discovery.ready;

    /// Cannot listen to the discovery event in background isolates
    /// Or an exception will be thrown:
    ///   Unsupported operation: Background isolates do not support setMessageHandler(). Messages from the host platform always go to the root isolate.
    discovery.eventStream!.listen((event) {
      // `eventStream` is not null as the discovery instance is "ready" !
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
        MyLogger.debug('${logPrefix} Service found : ${event.service?.toJson()}');
        event.service!.resolve(discovery.serviceResolver); // Should be called when the user wants to connect to this service.
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
        MyLogger.info('${logPrefix} Service resolved : ${event.service?.toJson()}');
        final service = event.service as ResolvedBonsoirService?;
        if(service == null) return;

        final host = service.host; // May be the host name, should be resolved to ip address
        final port = service.port;
        if(host == null) return;
        InternetAddress.lookup(host).then((values) {
          for(var ip in values) {
            if(ip.isLoopback) continue; // Ignore loopback address
            if(ip.type == InternetAddressType.IPv4) {
              _sendAnnounce(udp, ip, port, localIp.rawAddress, servicePort);
              break;
            }
          }
        });
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
        MyLogger.debug('${logPrefix} Service lost : ${event.service?.toJson()}');
      }
    });
    // Start the discovery **after** listening to discovery events :
    await discovery.start();

    _bonjourDiscovery = discovery;
  }

  int _generateId() {
    while(true) {
      int id = randomId();
      if(connectionPool.getConnectionById(id) != null) {
        continue;
      }
      if(incompletePool.doesConnectionIdExists(id)) { // In incompletePool, connection_id is used both as source_id and destination_id, so check both
        continue;
      }
      return id;
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