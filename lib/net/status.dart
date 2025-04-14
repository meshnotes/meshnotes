enum NetworkStatus {
  unknown,
  starting,
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
  String publicKey;
  String name;
  NodeStatus status;

  NodeInfo({
    required this.peer,
    required this.device,
    required this.publicKey,
    required this.name,
    required this.status,
  });

  @override
  String toString() {
    return '$peer:$device:$name';
  }

  String getShortDesc() {
    return '${publicKey.substring(0, 8)}($name)';
  }

  String getPublicKeyForShort() {
    if (publicKey.length <= 12) {
      return publicKey;
    }
    return '${publicKey.substring(0, 6)}...${publicKey.substring(publicKey.length - 6)}';
  }
  String getPublicKeyComplete() {
    return publicKey;
  }
}