import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/application/version_chain_api.dart';

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
  receiveVersionTreeConflict,
  receiveProvide,
  receiveQuery,
  uploadProgress,
  receiveOffer, // 6) Received generic offer message, currently type=storage
  sendApply, // 7) Send storage apply
}

class Message {
  Command cmd;
  dynamic parameter;
  TimeCostStatistics stats; // Statistics of transfer time and data size

  Message({
    required this.cmd,
    required this.parameter,
    required this.stats,
  });
}

class StartVillageParameter {
  String localPort;
  String serverList;
  String deviceId;
  UserPrivateInfo userInfo;
  bool useMulticast;
  String? logPath;
  bool allowSendingToPublicServer;

  StartVillageParameter({
    required this.localPort,
    required this.serverList,
    required this.deviceId,
    required this.userInfo,
    required this.useMulticast,
    this.logPath,
    this.allowSendingToPublicServer = false,
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
  String latestVersion;
  final String? transactionId;

  SendVersionTreeParameter({
    required this.versionChain,
    required this.timestamp,
    this.latestVersion = '',
    this.transactionId,
  });
}

class SendBroadcastParameter {
  final BroadcastMessages message;
  final String? resolvedVersion;
  final String? targetPublicKey;
  SendBroadcastParameter({required this.message, this.resolvedVersion, this.targetPublicKey});
}

class SendRequireVersionsParameter {
  List<String> versions;

  SendRequireVersionsParameter({
    required this.versions,
  });
}

class SendVersionsParameter {
  List<SendVersions> versions;
  final String? transactionId;
  final bool failed;

  SendVersionsParameter({
    required this.versions,
    this.transactionId,
    this.failed = false,
  });
}

class ReceiveProvideParameter {
  List<UnsignedResource> resources;

  ReceiveProvideParameter({
    required this.resources,
  });
}

class UploadProgressParameter {
  final int transferId;
  final int sent;
  final int total;
  final bool finished;
  const UploadProgressParameter(this.transferId, this.sent, this.total, this.finished);
}

class ReceiveQueryParameter {
  List<String> requiredObjects;
  final String? transactionId;

  ReceiveQueryParameter({
    required this.requiredObjects,
    this.transactionId,
  });
}