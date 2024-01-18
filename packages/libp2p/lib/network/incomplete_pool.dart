import 'dart:io';

import 'peer.dart';

class IncompleteTriple {
  InternetAddress ip;
  int port;
  int originalId;

  IncompleteTriple({
    required this.ip,
    required this.port,
    required this.originalId,
  });

  @override
  int get hashCode => Object.hash(ip, port, originalId);
  @override
  bool operator==(Object o) {
    return o is IncompleteTriple && o.ip == ip && o.port == port && o.originalId == originalId;
  }
}

class IncompletePool {
  Map<IncompleteTriple, Peer> _map = {};

  void addConnection(InternetAddress ip, int port, int id, Peer conn) {
    var key = IncompleteTriple(ip: ip, port: port, originalId: id);
    _map[key] = conn;
  }

  Peer? getConnection(InternetAddress ip, int port, int id) {
    var key = IncompleteTriple(ip: ip, port: port, originalId: id);
    return _map[key];
  }

  void removeConnection(InternetAddress ip, int port, int id) {
    var key = IncompleteTriple(ip: ip, port: port, originalId: id);
    _map.remove(key);
  }

  List<Peer> getAllConnections() {
    return _map.values.toList();
  }

  List<Peer> removeInvalidAndClosedConnections() {
    var result = <Peer>[];
    var toBeRemove = <IncompleteTriple>{};
    for(var entry in _map.entries) {
      var k = entry.key;
      var v = entry.value;
      var status = v.getStatus();
      if(status == ConnectionStatus.invalid || status == ConnectionStatus.shutdown) {
        result.add(v);
        toBeRemove.add(k);
      }
    }
    for(var item in toBeRemove) {
      _map.remove(item);
    }
    return result;
  }
}