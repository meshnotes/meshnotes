/// Run in a separated isolate

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:mesh_note/net/version_chain_api.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';
import '../mindeditor/setting/constants.dart';
import 'p2p_net.dart';
import 'package:libp2p/application/application_layer.dart';
import 'command.dart';
import 'status.dart';

class IsolateData {
  SendPort sendPort;
  RootIsolateToken token;

  IsolateData({
    required this.sendPort,
    required this.token,
  });
}

void netIsolateRunner(IsolateData _data) {
  // Init MyLogger in the separated isolate
  MyLogger.init(name: 'network');
  MyLogger.info('Running network isolate');

  BackgroundIsolateBinaryMessenger.ensureInitialized(_data.token);

  // Run version chain
  final versionChainVillager = VersionChainVillager(sendPort: _data.sendPort);
  versionChainVillager.start();
}

class VersionChainVillager {
  Village? _village;
  final SendPort _sendPort;
  Timer? _timer;
  SigningWrapper? _signing;
  VerifyingWrapper? _verify;
  EncryptWrapper? _encrypt;
  UserPrivateInfo? userPrivateInfo;

  VersionChainVillager({
    required SendPort sendPort,
  }): _sendPort = sendPort;

  void start() {
    var receivePort = ReceivePort();
    MyLogger.info('Sending SendPort to main isolate');
    // Exchange communication port
    _sendPort.send(receivePort.sendPort);

    // Handle messages from main isolate
    MyLogger.info('Start village protocol and listening');
    receivePort.listen((data) {
      if(data is Message) {
        _handleMessage(data);
      } else {
        MyLogger.info('Receive unrecognized message: $data');
      }
    });
    // Report node list for every 10 seconds
    _timer = Timer.periodic(const Duration(seconds: 10), _timerHandler);
  }

  void _handleMessage(Message msg) async {
    switch(msg.cmd) {
      case Command.terminate:
        //TODO Terminate village
        _timer?.cancel();
        _sendPort.send(Message(cmd: Command.terminateOk, parameter: null, stats: msg.stats));
        break;
      case Command.startVillage:
        if(_village != null) {
          return;
        }
        if(msg.parameter == null || msg.parameter is! StartVillageParameter) {
          return;
        }
        final parameter = msg.parameter as StartVillageParameter;
        if(parameter.logPath != null) {
          MyLogger.resetOutputToFile(path: parameter.logPath!);
        }
        userPrivateInfo = parameter.userInfo;
        _signing = SigningWrapper.loadKey(userPrivateInfo!.privateKey);
        _encrypt = EncryptWrapper(key: _signing!.key);
        _verify = VerifyingWrapper.loadKey(userPrivateInfo!.publicKey);
        VillageMessageHandler handler = VillageMessageHandler()
        // ..handleNewVersionTree = _handleNewVersionTree
        // ..handleRequireVersions = _handleRequireVersions
        // ..handleSendVersions = _handleSendVersions
          ..handleProvide = _handleProvide
          ..handleQuery = _handleQuery
          ..handlePublish = _handlePublish
        ;
        _village = await startVillage(
          localPort: parameter.localPort,
          serverList: parameter.serverList,
          deviceId: parameter.deviceId,
          userInfo: UserPublicInfo(publicKey: userPrivateInfo!.publicKey, userName: userPrivateInfo!.userName, timestamp: userPrivateInfo!.timestamp),
          connectedCallback: _nodeChanged,
          messageHandler: handler,
          useMulticast: parameter.useMulticast,
        );
        _sendPort.send(Message(cmd: Command.networkStatus, parameter: NetworkStatus.running, stats: msg.stats));
        _sendPort.send(Message(cmd: Command.villageStarted, parameter: null, stats: msg.stats));
        break;
      case Command.newNodeDiscovered:
        final param = msg.parameter as NewNodeDiscoveredParameter;
        _onNewNodeDiscovered(param.host, param.port, param.deviceId);
        break;
      case Command.villageStarted:
      case Command.terminateOk:
      case Command.networkStatus:
      case Command.nodeStatus:
      case Command.receiveBroadcast:
      case Command.receiveProvide:
      case Command.receiveQuery:
      // Do nothing, these commands are handled in net_controller
        break;
      case Command.sendBroadcast:
        final brdMsg = msg.parameter as BroadcastMessages;
        _onSendBroadcast(brdMsg, msg.stats);
        break;
      case Command.sendVersionTree:
        final param = msg.parameter as SendVersionTreeParameter;
        _onSendVersionTree(param.versionChain, param.timestamp, msg.stats);
        break;
      case Command.sendRequireVersions:
        final param = msg.parameter as SendRequireVersionsParameter;
        _onSendRequireVersions(param.versions, msg.stats);
        break;
      case Command.sendVersions:
        final sendVersions = msg.parameter as SendVersionsParameter;
        _onSendVersions(sendVersions.versions, msg.stats);
        break;
    }
  }

  final Map<String, NodeInfo> _nodes = {};
  final Map<VillagerStatus, NodeStatus> _statusMap = {
    VillagerStatus.keepInTouch: NodeStatus.inContact,
    VillagerStatus.lostContact: NodeStatus.lost,
  };

  void _nodeChanged(VillagerNode node) {
    NodeStatus _status = NodeStatus.unknown;
    final nodeStatus = node.getStatus();
    if(_statusMap.containsKey(nodeStatus)) {
      _status = _statusMap[nodeStatus]!;
    }
    final id = node.host + ':' + node.port.toString();
    final info = node.name;
    final publicKey = node.publicKey;
    final device = node.id;
    final nodeInfo = NodeInfo(peer: id, device: device, name: info, status: _status, publicKey: publicKey);
    _nodes[id] = nodeInfo;
    MyLogger.info('Node changed: $id: $nodeInfo');
    _reportNodes();
  }

  void _timerHandler(Timer _t) {
    if(_nodes.isEmpty) return;

    _reportNodes();
    _nodes.clear();
  }

  void _reportNodes() {
    final nodeList = _nodes.values.toList();
    final now = Util.getTimeStamp();
    _sendPort.send(Message(
      cmd: Command.nodeStatus,
      parameter: nodeList,
      stats: TimeCostStatistics(
        startTime: now,
        transportTime: now,
      ),
    ));
    _nodes.clear();
  }

  void _handleProvide(String data, TimeCostStatistics stats) {
    /// 1. Check public key is the same
    /// 2. Verify message and every single resource
    /// 3. Decrypt resources
    /// 4. Send to port to notify upper layer
    final processingTimer = Stopwatch()..start();
    final processStartTime = DateTime.now().microsecondsSinceEpoch;

    final signedResources = SignedResources.fromJson(jsonDecode(data));
    final publicKey = signedResources.userPublicId;
    if(publicKey != _signing!.getCompressedPublicKey()) {
      MyLogger.info('Receive provide message from other user: $publicKey');
      processingTimer.stop();
      return;
    }
    String feature = SignedResources.getFeature(signedResources.resources);
    final ok = _verifySignature(feature, signedResources.signature);
    if(!ok) {
      MyLogger.info('Verify provide message failed');
      processingTimer.stop();
      return;
    }

    final decryptStartTime = DateTime.now().microsecondsSinceEpoch;
    List<UnsignedResource> unsignedResourceList = [];
    int totalDataSize = 0;
    int decryptCount = 0;

    for(var resource in signedResources.resources) {
      UnsignedResource rawResource = UnsignedResource(
        key: resource.key,
        subKey: resource.subKey,
        timestamp: resource.timestamp,
        data: resource.data, // currently encrypted data
      );
      if(!_verifySignature(rawResource.getFeature(), resource.signature)) {
        MyLogger.info('Verify resource failed: ${rawResource.key}');
        continue;
      }
      var plainText = _encrypt!.decrypt(rawResource.timestamp, rawResource.data);
      rawResource.data = plainText;
      totalDataSize += plainText.length;
      decryptCount++;
      unsignedResourceList.add(rawResource);
    }

    final decryptEndTime = DateTime.now().microsecondsSinceEpoch;
    final decryptDuration = decryptEndTime - decryptStartTime;
    final totalProcessDuration = decryptEndTime - processStartTime;

    if (totalDataSize > 10240) { // Log only if > 10KB
      MyLogger.debug('[NetIsolate] _handleProvide: '
          'resources=$decryptCount, '
          'size=${(totalDataSize / 1024).toStringAsFixed(2)}KB, '
          'decrypt=${(decryptDuration / 1000).toStringAsFixed(2)}ms, '
          'total=${(totalProcessDuration / 1000).toStringAsFixed(2)}ms');
    }
    processingTimer.stop();
    final hasVersionTree = unsignedResourceList.any((resource) => resource.key == Constants.resourceKeyVersionTree);
    if(hasVersionTree) {
      stats.versionTreeCost += processingTimer.elapsedMilliseconds;
    } else {
      stats.versionCost += processingTimer.elapsedMilliseconds;
    }
    stats.transportTime = Util.getTimeStamp();
    _sendPort.send(Message(
      cmd: Command.receiveProvide,
      parameter: ReceiveProvideParameter(
        resources: unsignedResourceList,
      ),
      stats: stats,
    ));
  }

  void _handleQuery(String data, TimeCostStatistics stats) {
    /// 1. Check public key is the same
    /// 2. Verify message
    /// 3. Send to port to notify upper layer
    final processingTimer = Stopwatch()..start();
    SignedMessage signedMessage = SignedMessage.fromJson(jsonDecode(data));
    final publicKey = signedMessage.userPublicId;
    if(publicKey != _signing!.getCompressedPublicKey()) {
      MyLogger.info('Receive verify message from other user: $publicKey');
      processingTimer.stop();
      return;
    }
    if(!_verifySignature(signedMessage.data, signedMessage.signature)) {
      MyLogger.info('Verify query message failed');
      processingTimer.stop();
      return;
    }
    var requiredVersions = RequireVersions.fromJson(jsonDecode(signedMessage.data));
    processingTimer.stop();
    stats.requiredVersionsCost += processingTimer.elapsedMilliseconds;
    stats.transportTime = Util.getTimeStamp();
    _sendPort.send(Message(
      cmd: Command.receiveQuery,
      parameter: ReceiveQueryParameter(
        requiredObjects: requiredVersions.requiredVersions,
      ),
      stats: stats,
    ));
  }

  void _handlePublish(String data, TimeCostStatistics stats) {
    /// 1. Check public key is the same
    /// 2. Verify message
    /// 3. Send to port to notify upper layer
    SignedMessage signedMessage = SignedMessage.fromJson(jsonDecode(data));
    final publicKey = signedMessage.userPublicId;
    if(publicKey != _signing!.getCompressedPublicKey()) {
      MyLogger.info('Receive verify message from other user: $publicKey');
      return;
    }
    if(!_verifySignature(signedMessage.data, signedMessage.signature)) {
      MyLogger.info('Verify publish message failed');
      return;
    }
    var brdMsg = BroadcastMessages.fromJson(jsonDecode(signedMessage.data));
    stats.transportTime = Util.getTimeStamp();
    _sendPort.send(Message(
      cmd: Command.receiveBroadcast,
      parameter: brdMsg,
      stats: stats,
    ));
  }

  void _onNewNodeDiscovered(String host, int port, String deviceId) {
    MyLogger.info('New node detected: $host:$port, deviceId=$deviceId');
    _village?.newNodeDiscovered(host, port, deviceId);
  }

  void _onSendBroadcast(BroadcastMessages msg, TimeCostStatistics stats) {
    stats.receiveTime = Util.getTimeStamp();
    String json = jsonEncode(msg);
    String signature = _genSignature(json);
    SignedMessage signedMessage = SignedMessage(userPublicId: _signing!.getCompressedPublicKey(), data: json, signature: signature);
    String signedMessageJson = jsonEncode(signedMessage);
    _village?.sendPublish(signedMessageJson, stats);
  }

  void _onSendVersionTree(VersionChain versionChain, int timestamp, TimeCostStatistics stats) {
    final processingTimer = Stopwatch()..start();
    stats.receiveTime = Util.getTimeStamp();
    String chainJson = jsonEncode(versionChain);
    String encryptedChainJson = _encrypt!.encrypt(timestamp, chainJson);
    var rawResource = UnsignedResource(
      key: Constants.resourceKeyVersionTree,
      subKey: '',
      timestamp: timestamp,
      data: encryptedChainJson,
    );
    String signature = _genSignature(rawResource.getFeature());
    var signedResource = SignedResource.fromRaw(rawResource, signature);

    List<SignedResource> resourceList = [signedResource];
    String signatureOfList = _genSignature(SignedResources.getFeature(resourceList));
    SignedResources signedResources = SignedResources(userPublicId: _signing!.getCompressedPublicKey(), resources: resourceList, signature: signatureOfList);
    String signedResourcesJson = jsonEncode(signedResources);
    processingTimer.stop();
    stats.versionTreeCost += processingTimer.elapsedMilliseconds;
    _village?.sendVersionTree(signedResourcesJson, stats);
  }

  void _onSendRequireVersions(List<String> versions, TimeCostStatistics stats) {
    final processingTimer = Stopwatch()..start();
    stats.receiveTime = Util.getTimeStamp();
    var requiredVersions = RequireVersions(requiredVersions: versions);
    String json = jsonEncode(requiredVersions);
    String signature = _genSignature(json);
    SignedMessage signedMessage = SignedMessage(userPublicId: _signing!.getCompressedPublicKey(), data: json, signature: signature);
    String signedMessageJson = jsonEncode(signedMessage);
    processingTimer.stop();
    stats.requiredVersionsCost += processingTimer.elapsedMilliseconds;
    _village?.sendRequireVersions(signedMessageJson, stats);
  }

  void _onSendVersions(List<SendVersions> versions, TimeCostStatistics stats) {
    final processingTimer = Stopwatch()..start();
    stats.receiveTime = Util.getTimeStamp();
    List<SignedResource> resourceList = [];
    for(var version in versions) {
      String encryptedContent = _encrypt!.encrypt(version.createdAt, version.versionContent);
      UnsignedResource unsignedResource = UnsignedResource(
        key: version.versionHash,
        subKey: '',
        timestamp: version.createdAt,
        data: encryptedContent,
      );
      String signature = _genSignature(unsignedResource.getFeature());
      SignedResource signedResource = SignedResource.fromRaw(unsignedResource, signature);

      resourceList.add(signedResource);

      for(var item in version.requiredObjects.entries) {
        String hash = item.key;
        var object = item.value;
        String encryptedContent = _encrypt!.encrypt(object.createdAt, object.objContent);
        UnsignedResource rawObject = UnsignedResource(
          key: hash,
          subKey: '',
          timestamp: object.createdAt,
          data: encryptedContent,
        );
        String signature = _genSignature(rawObject.getFeature());
        SignedResource signedObject = SignedResource.fromRaw(rawObject, signature);

        resourceList.add(signedObject);
      }
    }
    String signature = _genSignature(SignedResources.getFeature(resourceList));
    final signedResources = SignedResources(userPublicId: _signing!.getCompressedPublicKey(), resources: resourceList, signature: signature);
    String json = jsonEncode(signedResources);

    processingTimer.stop();
    stats.versionCost += processingTimer.elapsedMilliseconds;
    _village?.sendVersions(json, stats);
  }

  String _genSignature(String text) {
    return _signing!.sign(HashUtil.hashText(text));
  }
  bool _verifySignature(String text, String stringSignature) {
    return _verify!.ver(HashUtil.hashText(text), stringSignature);
  }
}
