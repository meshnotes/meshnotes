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
  VillagerStatus _status = VillagerStatus.unknown;
  VillagerRole _role;
  Peer? _peer;

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
  }
  void setUnknown() {
    _status = VillagerStatus.unknown;
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
}