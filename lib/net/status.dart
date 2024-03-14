enum NetworkStatus {
  unknown,
  running,
}

enum NodeStatus {
  unknown,
  inContact,
  lost,
}

class NodeInfo {
  String peer;
  String device;
  String name;
  NodeStatus status;

  NodeInfo({
    required this.peer,
    required this.device,
    required this.name,
    required this.status,
  });

  @override
  String toString() {
    return '$peer:$device:$name';
  }
}