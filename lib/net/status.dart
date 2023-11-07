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
  String id;
  String name;
  NodeStatus status;

  NodeInfo({
    required this.id,
    required this.name,
    required this.status,
  });

  @override
  String toString() {
    return '$id:$name';
  }
}