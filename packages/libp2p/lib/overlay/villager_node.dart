import 'dart:io';

import '../network/peer.dart';

enum VillagerStatus {
  unknown, // untouched
  resolveFailed,
  resolved, // host name resolved
  contacting, // connecting to node
  keepInTouch, // connection is established
  lostContact, // connection lost, but can try to reconnect
}

enum VillagerRole {
  ordinary,
  wealthy,
  savant,
  head,
  monitor,
}

class VillagerNode {
  // Network properties
  bool isUpper;
  String nodeId = '';
  String host;
  InternetAddress? ip;
  int port;
  String id = '?';
  String name = '';
  VillagerStatus _status = VillagerStatus.unknown;
  VillagerRole _role;
  Peer? _peer;
  int failedTimestamp = 0;
  int currentReconnectIntervalInSeconds = defaultReconnectInterval;
  static int maxReconnectInterval = 60 * 5;
  static int defaultReconnectInterval = 5;

  VillagerNode({
    required this.host,
    required this.port,
    VillagerRole role = VillagerRole.ordinary,
    this.isUpper = false,
  }): _role = role;

  VillagerStatus getStatus() {
    return _status;
  }

  VillagerRole getRole() {
    return _role;
  }

  void setResolved(InternetAddress address) {
    ip = address;
    _status = VillagerStatus.resolved;
  }
  void setResolveFailed() {
    _status = VillagerStatus.resolveFailed;
  }
  void setConnecting() {
    _status = VillagerStatus.contacting;
  }
  void setConnected() {
    _status = VillagerStatus.keepInTouch;
    _resetReconnectInterval();
  }
  void setUnknown() {
    _status = VillagerStatus.unknown;
    _exponentialBackoff();
  }
  void setLost() {
    _status = VillagerStatus.lostContact;
    _exponentialBackoff();
  }

  void setPeer(Peer _p) {
    _peer = _p;
  }
  Peer? getPeer() {
    return _peer;
  }

  @override
  String toString() {
    return 'VillagerNode($host:$port)';
  }

  void _exponentialBackoff() {
    currentReconnectIntervalInSeconds *= 2;
    if(currentReconnectIntervalInSeconds > maxReconnectInterval) {
      currentReconnectIntervalInSeconds = maxReconnectInterval;
    }
  }
  void _resetReconnectInterval() {
    currentReconnectIntervalInSeconds = defaultReconnectInterval;
  }
}