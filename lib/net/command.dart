import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/net/version_chain_api.dart';

enum Command {
  terminate,
  terminateOk,
  startVillage,
  villageStarted,
  newNodeDiscovered,
  networkStatus,
  nodeStatus,
  sendBroadcast,
  sendVersionTree, // Send version tree
  // receiveVersionTree, // Receive version tree
  sendRequireVersions,
  // receiveRequiredVersions,
  sendVersions,
  // receiveVersions,
  receiveBroadcast,
  receiveProvide,
  receiveQuery,
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
  UserPrivateInfo userInfo;
  bool useMulticast;
  String? logPath;

  StartVillageParameter({
    required this.localPort,
    required this.serverList,
    required this.deviceId,
    required this.userInfo,
    required this.useMulticast,
    this.logPath,
  });
}

class NewNodeDiscoveredParameter {
  String host;
  int port;
  String deviceId;

  NewNodeDiscoveredParameter({
    required this.host,
    required this.port,
    required this.deviceId,
  });
}

class NewVersionParameter {
  String versionHash;
  String versionStr;
  Map<String, String> requiredObjects;

  NewVersionParameter({
    required this.versionHash,
    required this.versionStr,
    required this.requiredObjects
  });
}

class SendVersionTreeParameter {
  VersionChain versionChain;
  int timestamp;

  SendVersionTreeParameter({
    required this.versionChain,
    required this.timestamp,
  });
}

class SendRequireVersionsParameter {
  List<String> versions;

  SendRequireVersionsParameter({
    required this.versions,
  });
}

class SendVersionsParameter {
  List<SendVersions> versions;

  SendVersionsParameter({
    required this.versions,
  });
}

class ReceiveProvideParameter {
  List<UnsignedResource> resources;

  ReceiveProvideParameter({
    required this.resources,
  });
}

class ReceiveQueryParameter {
  List<String> requiredObjects;

  ReceiveQueryParameter({
    required this.requiredObjects,
  });
}