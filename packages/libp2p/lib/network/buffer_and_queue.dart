import 'dart:math';
import 'package:my_log/my_log.dart';
import '../utils.dart';
import 'protocol/frame.dart';
import 'protocol/packet.dart';


class RetryFrame {
  FrameData frame;
  int _lastSentTimestamp;
  int _resendCount = 0;

  RetryFrame({
    required this.frame,
  }): _lastSentTimestamp = networkNow();

  bool isBefore(int timestamp) {
    return _lastSentTimestamp <= timestamp;
  }
  void updateRetry() {
    _resendCount++;
    _lastSentTimestamp = networkNow();
    MyLogger.debug('updateRetry: updateResend() called, _resendCount=$_resendCount}');
  }
  int getResendCount() {
    return _resendCount;
  }
}

class RetryQueue {
  List<RetryFrame> messages = [];
  int maxMessageWindow;

  RetryQueue({
    required this.maxMessageWindow,
  });

  void ackFrame(int packetNumber, int objId, int seqNum) {
    List<RetryFrame> toBeDeleted = [];
    for(var msg in messages) {
      if(msg.frame.objId == objId && msg.frame.seqNum == seqNum) {
        toBeDeleted.add(msg);
        break;
      }
    }
    for(var msg in toBeDeleted) {
      messages.remove(msg);
    }
  }

  bool enqueue(FrameData frame) {
    // if(messages.length >= maxMessageWindow) return false;
    var msg = RetryFrame(frame: frame);
    messages.add(msg);
    return true;
  }

  List<RetryFrame> getAllTimeoutFrame(int timestamp) {
    List<RetryFrame> result = [];
    for(var msg in messages) {
      if(msg.isBefore(timestamp)) {
        result.add(msg);
      }
    }
    return result;
  }

  int getAvailableSize() {
    int available = maxMessageWindow - messages.length;
    if(available > 0) {
      return available;
    }
    return 0;
  }
}

class ControlQueue {
  PacketConnect? _packetConnect;
  int _connectTime = 0;
  int _connectRetryCount = 0;

  void setConnect(PacketConnect _connect) {
    _packetConnect = _connect;
    _connectTime = networkNow();
    _connectRetryCount = 0;
  }
  void clearConnect() {
    clearAll();
  }
  void setConnectAck(PacketConnect _connectAck) {
    _packetConnect = _connectAck;
    _connectTime = networkNow();
    _connectRetryCount = 0;
  }
  void clearConnectAck() {
    clearAll();
  }
  void clearAll() {
    _packetConnect = null;
    _connectTime = 0;
    _connectRetryCount = 0;
  }
  List<Packet> getRetryPacketIfTimeout(int timestamp) {
    List<Packet> result = [];
    if(_connectTime < timestamp && _packetConnect != null) {
      result.add(_packetConnect!);
      _connectRetryCount++;
      _connectTime = networkNow();
    }
    return result;
  }
  List<Packet> getAllPackets() {
    List<Packet> result = [];
    if(_packetConnect != null) {
      result.add(_packetConnect!);
    }
    return result;
  }
  int getConnectRetryCount() {
    return _connectRetryCount;
  }
  int getLastConnectTime() {
    return _connectTime;
  }
}

class ReceivedMsg implements Updatable {
  List<List<int>?> buffer;
  int objId;
  int seqNum;
  int total;

  ReceivedMsg({
    required this.objId,
    required this.seqNum,
    required this.total,
    required List<int> data,
  }): buffer = List.filled(total, null) {
    buffer[seqNum] = data;
  }

  // Replace buffer[seqNum] by the corresponding slot in obj, if and only if two pieces of data are consist
  @override
  void update(Updatable obj) {
    if(obj is! ReceivedMsg) {
      //TODO add log
      return;
    }
    ReceivedMsg msg = obj;
    if(total != msg.total) {
      //TODO add log
      return;
    }
    if(msg.seqNum < 0 || msg.seqNum >= total) {
      //TODO add log
      return;
    }
    if(msg.buffer[msg.seqNum] == null) {
      //TODO add log
      return;
    }
    buffer[msg.seqNum] = msg.buffer[msg.seqNum];
  }

  // If all the slot of buffer is not null, then it is complete
  @override
  bool isComplete() {
    for(int i = 0; i < total; i++) {
      if(buffer[i] == null) return false;
    }
    return true;
  }
}

class ReceiveQueue {
  CycledQueue<ReceivedMsg> buffer;
  int maxBufferWindow;
  int minObjectId = 0;

  ReceiveQueue({
    required this.maxBufferWindow,
  }): buffer = CycledQueue(size: maxBufferWindow);

  /** Procedure:
   *  0. If objId exceeds max buffer window, just return false.
   *    0.1 If objId is less than minSequenceNumber, maybe it's resend data, just return true.
   *  1. If the corresponding data in the buffer is done or is ready, that means we have already handled it, just return true.
   *  2. Update the corresponding data in the buffer, and return true.
   *
   * Return value:
   *   true - send ACK.
   *   false - don't send ACK.
   */
  bool enqueue(int objId, int seqNumber, int total, List<int> data) {
    if(objId >= minObjectId + maxBufferWindow) return false;
    if(objId < minObjectId) return true;

    final index = objId - minObjectId;
    if(buffer.isDone(index) || buffer.isReady(index)) {
      return true;
    }
    ReceivedMsg msg = ReceivedMsg(objId: objId, seqNum: seqNumber, total: total, data: data);
    buffer.update(index, msg);
    return true;
  }

  bool isDone(int objId) {
    if(objId >= minObjectId + maxBufferWindow) return false;
    if(objId < minObjectId) return true;
    final index = objId - minObjectId;
    return buffer.isDone(index);
  }

  List<List<int>> popAvailableData() {
    List<ReceivedMsg> messages = buffer.getAllReadyDataAndSetDone();
    List<List<int>> result = [];
    for(var msg in messages) {
      var data = _mergeData(msg);
      if(data.length > 0) {
        result.add(data);
      }
    }
    int count = buffer.popHeadingDone();
    minObjectId += count;
    return result;
  }

  List<int> _mergeData(ReceivedMsg msg) {
    List<int> result = [];
    for(var i = 0; i < msg.buffer.length; i++) {
      var data = msg.buffer[i];
      if(data == null) continue; // This is impossible
      result.addAll(data);
    }
    return result;
  }
}

abstract class Updatable {
  void update(Updatable obj);
  bool isComplete();
}

// Cycled queue
class CycledQueue<T extends Updatable> {
  static const int _defaultSize = 32;
  static const int _none = 0;
  static const int _updating = 1;
  static const int _ready = 2;
  static const int _done = 3;
  List<T?> queue = [];
  List<int> map = [];
  int size;
  int head = 0;

  CycledQueue({
    required this.size,
  }): head = 0 {
    if(size <= 0) {
      size = _defaultSize;
    }
    queue = List.filled(size, null);
    map = List.filled(size, _none);
  }

  int getSize() {
    return size;
  }
  bool isDone(int index) {
    return _isInState(index, _done);
  }
  bool isReady(int index) {
    return _isInState(index, _ready);
  }
  bool _isInState(int index, int state) {
    if(index >= 0 && index < size) {
      return map[index] == state;
    }
    return false;
  }

  void update(int index, T obj) {
    // 1. Only update data if the status is _none or _updating
    // 2. If data slot is null, then replace it with obj
    // 3. If data slot is not null, then update it with obj
    // 4. If data is complete, then set the status to _ready
    if(index < 0 || index >= size) return;
    if(map[index] == _done || map[index] == _ready) return;
    if(queue[index] != null) {
      queue[index]!.update(obj);
    } else {
      queue[index] = obj;
    }
    map[index] = _updating;
    if(queue[index]!.isComplete()) {
      map[index] = _ready;
    }
  }

  List<T> getAllReadyDataAndSetDone() {
    List<T> result = [];
    for(var i = 0; i < size; i++) {
      int idx = (head + i) % size;
      if(map[idx] == _ready && queue[idx] != null) {
        result.add(queue[idx]!);
        map[idx] = _done;
      }
    }
    return result;
  }

  int popHeadingDone() {
    int count = 0;
    for(var i = 0; i < size; i++) {
      int idx = head + i;
      if(map[idx] != _done) break;
      count++;
      map[idx] = _none;
      queue[idx] = null;
    }
    head += count;
    return count;
  }
}

class SendQueue {
  List<Frame> buffer = [];
  void pushFrame(Frame frame) {
    buffer.add(frame);
  }

  List<Frame> popAllFrames() {
    var result = buffer;
    buffer = [];
    return result;
  }
}

class DataBuffer {
  List<Frame> buffer = [];

  bool isAvailable(int size) {
    return true;
  }
  void enqueue(List<Frame> list) {
    buffer.addAll(list);
  }
  List<Frame> popAtMost(int size) {
    size = min(size, buffer.length);
    List<Frame> result = buffer.sublist(0, size);
    buffer.removeRange(0, size);
    return result;
  }
}