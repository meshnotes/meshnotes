enum Command {
  terminate,
  terminateOk,
  startVillage,
  networkStatus,
  nodeStatus,
  sendVersionTree, // Send version tree
  receiveVersionTree, // Receive version tree
}

class Message {
  Command cmd;
  dynamic parameter;

  Message({
    required this.cmd,
    required this.parameter,
  });
}

class StartVillageParameter {
  String localPort;
  String serverList;
  String deviceId;

  StartVillageParameter({
    required this.localPort,
    required this.serverList,
    required this.deviceId,
  });
}

class NewVersionTreeParameter {
  String versionHash;
  String versionStr;
  Map<String, String> requiredObjects;

  NewVersionTreeParameter({
    required this.versionHash,
    required this.versionStr,
    required this.requiredObjects
  });
}