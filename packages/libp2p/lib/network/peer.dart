import 'dart:io';
import 'protocol/packet.dart';
import 'package:libp2p/network/buffer_and_queue.dart';
import 'package:libp2p/utils.dart';
import 'protocol/frame.dart';
import '../constants.dart';
import 'package:my_log/my_log.dart';

class ConnectionController {
  Function(Peer)? onConnectSucceed;
  Function(Peer)? onConnectFailed;
  Function(Peer, List<int>)? onReceiveData;
  Function(Peer)? onClosed;
}

enum ConnectionStatus {
  invalid, // connect fail or heartbeat timeout
  initializing, // after connect package was sent
  establishing, // after connect_ack package was sent
  established, // after connected package was sent or received
  shutdown, // closed by one peer
}

typedef OnReceiveDataCallback = void Function(List<int> data);
typedef OnDisconnectCallback = void Function(Peer);
typedef OnConnectionFail = void Function(Peer);

class Peer {
  static const logPrefix = '[Peer]';

  DataBuffer dataBuffer = DataBuffer();
  RetryQueue retryQueue = RetryQueue(maxMessageWindow: initialSendingWindow);
  ReceiveQueue receiveQueue = ReceiveQueue(maxBufferWindow: initialReceivingWindow);
  SendQueue sendQueue = SendQueue();
  ControlQueue controlQueue = ControlQueue();

  InternetAddress ip;
  int port;
  int maxHeartbeat = 30000;
  int maxRetryCount = 5;
  ConnectionStatus _status = ConnectionStatus.invalid;
  ConnectionStatus getStatus() => _status;
  int _sourceId = 0;
  int _destinationId = 0;
  int sendPacketNumber = randomInitialPacketNumber();
  int nextObjectId = 0;
  int receivePacketNumber = 0;
  int _lastContact = 0;
  int _lastHeartbeat = 0;
  OnReceiveDataCallback? onReceiveData;
  OnDisconnectCallback? onDisconnect;
  OnConnectionFail? onConnectionFail;
  int Function(List<int>, InternetAddress, int) _transport;
  bool alreadyScheduledNotifier = false;

  Peer({
    required this.ip,
    required this.port,
    required int Function(List<int>, InternetAddress, int) transport,
    this.onReceiveData,
    this.onDisconnect,
    this.onConnectionFail,
  }): _transport = transport;

  void setInitializing() => _status = ConnectionStatus.initializing;
  void setEstablishing() => _status = ConnectionStatus.establishing;
  void setEstablished() => _status = ConnectionStatus.established;
  void setInvalid() => _status = ConnectionStatus.invalid;
  void setShutdown() => _status = ConnectionStatus.shutdown;

  PacketHeader _buildPacketHeader(PacketType type) {
    return PacketHeader(type: type, destConnectionId: _destinationId, packetNumber: 0);
  }
  connect() async {
    _sendConnectMsg();
  }
  _sendConnectMsg() async {
    var packet = PacketConnect(
      header: _buildPacketHeader(PacketType.connect),
      sourceConnectionId: _sourceId,
    );
    controlQueue.setConnect(packet);
    _sendPacket(packet);
  }

  bool onConnect(PacketConnect packet) {
    var status = getStatus();
    if(status != ConnectionStatus.invalid && status != ConnectionStatus.establishing) {
      MyLogger.warn('${logPrefix} Invalid status on connect: status=$_status');
      return false;
    }
    receivePacketNumber = packet.header.packetNumber;
    _sendConnectAck();
    return true;
  }
  _sendConnectAck() async {
    var packet = PacketConnect(
      header: _buildPacketHeader(PacketType.connectAck),
      sourceConnectionId: _sourceId,
    );
    controlQueue.setConnectAck(packet);
    _sendPacket(packet);
  }

  bool onConnectAck(PacketConnect packet) {
    // 1. 将connection状态置为established
    // 2. 从发送队列中清理connect消息
    // 3. 发送connected消息
    var status = getStatus();
    if(status != ConnectionStatus.initializing && status != ConnectionStatus.established) {
      MyLogger.warn('${logPrefix} Invalid status on connect_ack: status=$_status');
      return false;
    }
    // 对于被动连接方，收到connect_ack消息时第一次获得对方的packetNumber
    var packetNumber = packet.header.packetNumber;
    // 如果receivePacketNumber不为0，说明已经被设置过
    if(receivePacketNumber != 0 && packetNumber != receivePacketNumber) {
      MyLogger.warn('${logPrefix} Packet number in connect_ack message inconsistent($packetNumber vs $receivePacketNumber). Use newer value');
    }
    receivePacketNumber = packetNumber;
    setDestinationId(packet.sourceConnectionId);
    if(status == ConnectionStatus.initializing) {
      setEstablished();
      _updateContact();
      _updateHeartbeat();
    }
    controlQueue.clearConnect();
    _sendConnectedMsg();
    return true;
  }
  _sendConnectedMsg() {
    var packet = PacketConnect(
      header: _buildPacketHeader(PacketType.connected),
      sourceConnectionId: _sourceId,
    );
    _sendPacket(packet);
  }
  void _sendBye() {
    var packet = PacketBye(
      tag: PacketBye.tagBye,
      header: _buildPacketHeader(PacketType.bye),
    );
    _sendPacket(packet);
  }

  bool onConnected(PacketConnect packet) {
    // 1. 确认connection状态为establishing
    // 2. 将connection状态置为established
    // 3. 从发送队列中清理connect_ack消息
    // 4. Update _lastContact timestamp
    if(getStatus() != ConnectionStatus.establishing) {
      MyLogger.warn('${logPrefix} Invalid status on connected: status=$_status');
      return false;
    }
    // 对于主动连接方，收到connected消息时第二次获得对方的packetNumber
    var packetNumber = packet.header.packetNumber;
    if(receivePacketNumber != 0 && packetNumber != receivePacketNumber) {
      MyLogger.warn('${logPrefix} Packet number in connected message inconsistent($packetNumber vs $receivePacketNumber). Use newer value');
    }
    receivePacketNumber = packetNumber;
    setEstablished();
    controlQueue.clearConnectAck();
    _updateContact();
    _updateHeartbeat();
    return true;
  }

  _sendDataAck(int packetNumber, int objId, int seqNum) {
    var frame = FrameAck(
      packetNumber: packetNumber,
      objId: objId,
      seqNum: seqNum,
    );
    _enqueueSend(frame);
  }

  bool onData(PacketData packet) {
    _updateContact();
    final frames = packet.frames;
    for(var frame in frames) {
      switch(frame.type) {
        case FrameType.dataFrame:
          // 1. Put into receive queue
          // 2. Notify upper layer
          // 3. Send back ACK message
          var dataFrame = frame as FrameData;
          final objId = dataFrame.objId;
          final seqNumber = dataFrame.seqNum;
          final total = dataFrame.total;
          final data = dataFrame.data;
          bool needAck = receiveQueue.enqueue(objId, seqNumber, total, data);
          if(!needAck) break;
          _sendDataAck(packet.header.packetNumber, frame.objId, frame.seqNum);

          MyLogger.verbose('${logPrefix} Data in peer.onData(): $data');
          // If this object has already been notified, do nothing.
          // Or we should check if any object is ready to notify upper layer.
          if(receiveQueue.isDone(objId)) break;
          if (!alreadyScheduledNotifier) {
            alreadyScheduledNotifier = true; // Avoid running Future many times
            MyLogger.verbose('${logPrefix} Notify upper layer');
            _notifyUpperLayerOnReceivedData();
          }
          break;
        case FrameType.ackFrame:
          // 1. Clear send queue
          var ackFrame = frame as FrameAck;
          final packetNumber = ackFrame.packetNumber;
          final objId = ackFrame.objId;
          final seqNum = ackFrame.seqNum;
          retryQueue.ackFrame(packetNumber, objId, seqNum);
          MyLogger.debug('${logPrefix} ack for $objId, $seqNum, retryQueue now has ${retryQueue.messages.length} messages');
          _tryToSendIfRetryAvailable();
          break;
        case FrameType.heartbeatFrame:
          // If it's heartbeat request, then send a response. Ignore it otherwise.
          // There is no need to update last contact time, because it is already done.
          var heartbeatFrame = frame as FrameHeartbeat;
          if(heartbeatFrame.isRequest()) {
            _sendHeartbeatResponse();
          }
          break;
        case FrameType.invalidFrame:
          break;
      }
    }
    return true;
  }

  void onClose() {
    _disconnect();
  }

  Future<void> _notifyUpperLayerOnReceivedData() async {
    alreadyScheduledNotifier = false;
    var availableData = receiveQueue.popAvailableData();
    if(onReceiveData == null) {
      // TODO May be should not drop data here
      MyLogger.verbose('${logPrefix} Drop data since _onReceiveData is null');
      return;
    }
    for(var data in availableData) {
      onReceiveData!(data);
    }
  }

  // 对超出MTU的消息进行分包发送
  bool sendData(List<int> data) {
    if(data.length == 0) return false;

    List<List<int>> splits = _splitData(data);
    if(!dataBuffer.isAvailable(splits.length)) return false;

    List<FrameData> frames = _buildFrames(splits);
    dataBuffer.enqueue(frames);
    _tryToSendIfRetryAvailable();
    return true;
  }

  List<List<int>> _splitData(List<int> data) {
    final len = data.length;
    List<List<int>> frames = [];
    int start = 0;
    while(start < len) {
      int end = start + maxPackageSize;
      if(end > len) {
        end = len;
      }
      var frame = data.sublist(start, end);
      frames.add(frame);
      start = end;
    }
    return frames;
  }
  List<FrameData> _buildFrames(List<List<int>> dataSet) {
    final objId = _nextObjId();
    final total = dataSet.length;
    List<FrameData> result = [];
    for(int i = 0; i < total; i++) {
      var data = dataSet[i];
      var frame = FrameData(
        objId: objId,
        seqNum: i,
        total: total,
        data: data,
      );
      result.add(frame);
    }
    return result;
  }

  int _nextObjId() {
    return nextObjectId++;
  }

  void _sendPacket(Packet packet) {
    packet.setPacketNumber(sendPacketNumber++);
    final bytes = packet.toBytes();
    // MyLogger.debug('${logPrefix} Sending ${packet.getType().name} message: $bytes');
    _transportSend(bytes);
  }

  void updateResendQueue(int timeoutThreshold) {
    var timeOutMessages = retryQueue.getAllTimeoutFrame(timeoutThreshold);
    for(var msg in timeOutMessages) {
      msg.updateRetry();
      _enqueueSend(msg.frame);
    }
    _tryToSendIfRetryAvailable();
  }

  void _tryToSendIfRetryAvailable() {
    int size = retryQueue.getAvailableSize();
    if(size <= 0) return;
    var frames = dataBuffer.popAtMost(size);

    // If it is data frame, add to resend queue, and then add to send queue.
    // If not, just add to send queue.
    for(var frame in frames) {
      if (frame.type == FrameType.dataFrame) {
        retryQueue.enqueue(frame as FrameData);
      }
      _enqueueSend(frame);
    }
  }

  void _enqueueSend(Frame frame) {
    sendQueue.pushFrame(frame);
    Future(() {
      var waitingList = sendQueue.popAllFrames();
      // TODO add frame packaging here
      for(var frame in waitingList) {
        var packet = PacketData(frames: [frame], header: _buildPacketHeader(PacketType.data));
        _sendPacket(packet);
      }
    });
  }

  void _transportSend(List<int> bytes) {
    _transport(bytes, ip, port);
  }

  void updateControlQueue(int timeoutThreshold) {
    // 1. If status is established and exceeds 5 heartbeat timer, end the connection
    // 2. If status is established and heartbeat timer expired, send heartbeat
    // 3. If status is not established, and retry count exceeds maxRetryCount, shut it down
    // 4. If status is not established, and control queue is not empty, resend all timeout connect packages
    if(_status == ConnectionStatus.established) {
      final now = networkNow();
      final lastContactInterval = now - _lastContact;
      if(lastContactInterval >= 5 * maxHeartbeat) {
        MyLogger.info('${logPrefix} Connection failed due to heartbeat lost, now=$now, _lastContact=$_lastContact, maxHeartbeat=$maxHeartbeat');
        _connectFailed();
        return;
      }
      final lastHeartbeatInterval = now - _lastHeartbeat;
      if (lastHeartbeatInterval >= maxHeartbeat) {
        MyLogger.debug('${logPrefix} Send heartbeat, now=$now, _lastHeartbeat=$_lastHeartbeat, maxHeartbeat=$maxHeartbeat');
        _sendHeartbeat();
      }
    } else if(_status != ConnectionStatus.invalid) {
      int retryCount = controlQueue.getConnectRetryCount();
      if(retryCount >= maxRetryCount) {
        MyLogger.info('${logPrefix} Connection failed due to exceed max retry count');
        controlQueue.clearAll();
        _connectFailed();
      } else {
        var retryPackets = controlQueue.getRetryPacketIfTimeout(timeoutThreshold);
        if(retryPackets.isNotEmpty) {
          MyLogger.debug('${logPrefix} Resend packets, retry for ${retryCount + 1} time');
        }
        for (var packet in retryPackets) {
          _sendPacket(packet);
        }
      }
    }
  }

  void _sendHeartbeat() {
    var frame = FrameHeartbeat.request();
    _enqueueSend(frame);
    _updateHeartbeat();
  }
  void _sendHeartbeatResponse() {
    var frame = FrameHeartbeat.response();
    _enqueueSend(frame);
  }

  void _disconnect() {
    if(_status == ConnectionStatus.shutdown) return;
    onDisconnect?.call(this);
    setShutdown();
  }
  void _connectFailed() {
    if(_status == ConnectionStatus.invalid) return;
    onConnectionFail?.call(this);
    setInvalid();
  }

  void _updateContact() {
    _lastContact = networkNow();
  }
  void _updateHeartbeat() {
    _lastHeartbeat = networkNow();
  }
  int getLastContactTime() => _lastContact;

  int getSourceId() {
    return _sourceId;
  }
  void setSourceId(int sourceId) {
    _sourceId = sourceId;
  }
  int getDestinationId() {
    return _destinationId;
  }
  void setDestinationId(int destId) {
    _destinationId = destId;
  }
  void close() {
    _sendBye();
    _disconnect();
  }

  void setOnReceive(OnReceiveDataCallback? _func) {
    onReceiveData = _func;
  }
  void setOnDisconnect(OnDisconnectCallback? _func) {
    onDisconnect = _func;
  }
  void setOnConnectFail(OnConnectionFail? _func) {
    onConnectionFail = _func;
  }
}

class ConnectionPool {
  Map<int, Peer> _connectionIdMap = {};

  Peer? getConnectionById(int sourceConnectionId) {
    return _connectionIdMap[sourceConnectionId];
  }

  void addConnection(Peer c) {
    var sourceConnectionId = c.getSourceId();
    _connectionIdMap[sourceConnectionId] = c;
  }

  void removeConnection(Peer c) {
    var sourceConnectionId = c.getSourceId();
    _connectionIdMap.remove(sourceConnectionId);
  }

  List<Peer> getAllConnections() {
    return _connectionIdMap.values.toList();
  }

  List<Peer> removeInvalidAndClosedConnections() {
    var result = <Peer>[];
    var toBeRemove = <int>{};
    for(var entry in _connectionIdMap.entries) {
      var k = entry.key;
      var v = entry.value;
      var status = v.getStatus();
      if(status == ConnectionStatus.invalid || status == ConnectionStatus.shutdown) {
        result.add(v);
        toBeRemove.add(k);
      }
    }
    for(var item in toBeRemove) {
      _connectionIdMap.remove(item);
    }
    return result;
  }
}