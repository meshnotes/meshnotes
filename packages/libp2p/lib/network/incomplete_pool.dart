import 'dart:io';

import 'peer.dart';

class IncompleteTriple {
  InternetAddress ip;
  int port;
  int connectionId; // Very special here: this may be the remote connection_id(when receiving connect) or the local connection_id(when sending connect)

  IncompleteTriple({
    required this.ip,
    required this.port,
    required this.connectionId,
  });

  @override
  int get hashCode => Object.hash(ip, port, connectionId);
  @override
  bool operator==(Object o) {
    return o is IncompleteTriple && o.ip == ip && o.port == port && o.connectionId == connectionId;
  }
}

class IncompletePool {
  Map<IncompleteTriple, Peer> _map = {};

  void addConnection(InternetAddress ip, int port, int id, Peer conn) {
    var key = IncompleteTriple(ip: ip, port: port, connectionId: id);
    _map[key] = conn;
  }

  Peer? getConnection(InternetAddress ip, int port, int id) {
    var key = IncompleteTriple(ip: ip, port: port, connectionId: id);
    return _map[key];
  }

  Peer? getConnectionByIpAndPort(InternetAddress ip, int port) {
    for(var entry in _map.values) {
      if(entry.ip == ip && entry.port == port) {
        return entry;
      }
    }
    return null;
  }

  void removeConnection(InternetAddress ip, int port, int id) {
    var key = IncompleteTriple(ip: ip, port: port, connectionId: id);
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

  bool doesConnectionIdExists(int id) {
    for(var entry in _map.values) {
      if(entry.getSourceId() == id || entry.getDestinationId() == id) {
        return true;
      }
    }
    return false;
  }
}