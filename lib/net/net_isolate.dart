/// Run in a separated isolate

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:libp2p/application/version_chain_api.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';
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
  final Map<String, VerifyingWrapper> _verifyMap = {};
  EncryptWrapper? _encrypt;
  UserPrivateInfo? userPrivateInfo;
  bool _allowSendingToPublicServer = false;

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
        _allowSendingToPublicServer = parameter.allowSendingToPublicServer;
        _signing = SigningWrapper.loadKey(userPrivateInfo!.privateKey);
        _encrypt = EncryptWrapper(key: _signing!.key);
        _verify = VerifyingWrapper.loadKey(userPrivateInfo!.publicKey);
        VillageMessageHandler handler = VillageMessageHandler()
        // ..handleNewVersionTree = _handleNewVersionTree
        // ..handleRequireVersions = _handleRequireVersions
        // ..handleSendVersions = _handleSendVersions
          ..handleProvide = _onReceivedProvide
          ..handleQuery = _onReceivedQuery
          ..handlePublish = _onReceivedPublish
          ..handleOffer = _onReceivedOffer
          ..handleApply = _onReceivedApply
        ;
        _village = await startVillage(
          localPort: parameter.localPort,
          serverList: parameter.serverList,
          deviceId: parameter.deviceId,
          userInfo: UserPublicInfo(publicKey: userPrivateInfo!.publicKey, userName: userPrivateInfo!.userName, timestamp: userPrivateInfo!.timestamp),
          connectedCallback: _nodeChanged,
          messageHandler: handler,
          useMulticast: parameter.useMulticast,
          allowSendingToPublicServer: parameter.allowSendingToPublicServer,
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
      case Command.receiveOffer: // Handled in net_controller
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
      case Command.sendApply: // 7) sendApply is handled in net_isolate
        final applyDataStr = msg.parameter as String;
        _onSendApply(applyDataStr, msg.stats);
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

  void _onReceivedProvide(String senderPublicKey, String data, TimeCostStatistics stats) {
    /// 1. Check public key is the same
    /// 2. Verify message and every single resource
    /// 3. Decrypt resources
    /// 4. Send to port to notify upper layer
    final processingTimer = Stopwatch()..start();
    final processStartTime = DateTime.now().microsecondsSinceEpoch;

    final cipherMessages = CipherMessages.fromJson(jsonDecode(data));
    if(cipherMessages.userPublicId != senderPublicKey) {
      MyLogger.info('Receive PROVIDE message not signed by its sender');
      processingTimer.stop();
      return;
    }
    String feature = CipherMessages.getFeature(cipherMessages.resources);
    final ok = _verifySignatureWithKey(senderPublicKey, feature, cipherMessages.signature);
    if(!ok) {
      MyLogger.info('Verify PROVIDE message failed');
      processingTimer.stop();
      return;
    }

    final decryptStartTime = DateTime.now().microsecondsSinceEpoch;
    List<UnsignedResource> unsignedResourceList = [];
    int totalDataSize = 0;
    int decryptCount = 0;

    for(var resource in cipherMessages.resources) {
      UnsignedResource rawResource = UnsignedResource(
        key: resource.key,
        subKey: resource.subKey,
        timestamp: resource.timestamp,
        data: resource.data, // currently encrypted data
      );
      if(!_verifySignature(rawResource.getFeature(), resource.signature)) {
        MyLogger.info('Verify PROVIDE resource failed: ${rawResource.key}');
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

    if(totalDataSize > 10240) { // Log only if > 10KB
      MyLogger.debug('[NetIsolate] _handleProvide: '
          'resources=$decryptCount, '
          'size=${(totalDataSize / 1024).toStringAsFixed(2)}KB, '
          'decrypt=${(decryptDuration / 1000).toStringAsFixed(2)}ms, '
          'total=${(totalProcessDuration / 1000).toStringAsFixed(2)}ms');
    }
    processingTimer.stop();
    final hasVersionTree = unsignedResourceList.any((resource) => resource.key == resourceKeyVersionTree);
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

  void _onReceivedQuery(String senderPublicKey, String data, TimeCostStatistics stats) {
    /// 1. Check public key is the same
    /// 2. Verify message
    /// 3. Send to port to notify upper layer
    final processingTimer = Stopwatch()..start();
    UncipherMessage uncipherMessage = UncipherMessage.fromJson(jsonDecode(data));
    final publicKey = uncipherMessage.userPublicId;
    if(publicKey != senderPublicKey) {
      MyLogger.info('Receive QUERY message not signed by its sender');
      return;
    }
    if(publicKey != _signing!.getCompressedPublicKey() && !_allowSendingToPublicServer) {
      // 4) Query is an unciphered data request. In public-server mode a storage node with a different public key may query this user's data.
      // Gate that cross-user query path behind allowSendingToPublicServer, then verify with the requester's public key.
      MyLogger.info('Receive QUERY message from other user, and it is not allowed');
      processingTimer.stop();
      return;
    }
    if(!_verifySignatureWithKey(senderPublicKey, uncipherMessage.data, uncipherMessage.signature)) {
      MyLogger.info('Verify QUERY message failed');
      processingTimer.stop();
      return;
    }
    var requiredVersions = RequireVersions.fromJson(jsonDecode(uncipherMessage.data));
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

  void _onReceivedPublish(String senderPublicKey, String data, TimeCostStatistics stats) {
    /// 1. Check public key is the same
    /// 2. Verify the hole message by the sender's public key
    /// 3. Verify the data by the data owner's signature
    /// 4. Send to port to notify upper layer
    UncipherMessage uncipherMessage = UncipherMessage.fromJson(jsonDecode(data));
    final publicKey = uncipherMessage.userPublicId;
    if(publicKey != senderPublicKey) {
      MyLogger.info('Receive PUBLISH message not signed by its sender');
      return;
    }
    if(!_verifySignatureWithKey(senderPublicKey, uncipherMessage.data, uncipherMessage.signature)) {
      MyLogger.info('Verify PUBLISH message failed');
      return;
    }
    var brdMsg = BroadcastMessages.fromJson(jsonDecode(uncipherMessage.data));
    final ownerPublicKey = brdMsg.userPublicId;
    if(ownerPublicKey != _signing!.getCompressedPublicKey()) {
      MyLogger.info('Drop PUBLISH message from other user');
      return;
    }
    if(!_verifySignature(brdMsg.toSignableString(), brdMsg.signature)) {
      MyLogger.info('Verify PUBLISH message with the data owner\'s signature failed');
      return;
    }
    stats.transportTime = Util.getTimeStamp();
    _sendPort.send(Message(
      cmd: Command.receiveBroadcast,
      parameter: brdMsg,
      stats: stats,
    ));
  }

  void _onSendBroadcast(BroadcastMessages msg, TimeCostStatistics stats) {
    stats.receiveTime = Util.getTimeStamp();
    msg.userPublicId = _signing!.getCompressedPublicKey();
    msg.signature = _genSignature(msg.toSignableString()); // This is the signature of the data owner
    String json = jsonEncode(msg);
    String signature = _genSignature(json); // This is the signature of the sender. Sometimes they are different, for example, in the server mode.
    UncipherMessage uncipherMessage = UncipherMessage(userPublicId: _signing!.getCompressedPublicKey(), data: json, signature: signature);
    String uncipherMessageJson = jsonEncode(uncipherMessage);
    _village?.sendPublish(uncipherMessageJson, stats);
  }

  void _onSendVersionTree(VersionChain versionChain, int timestamp, TimeCostStatistics stats) {
    final processingTimer = Stopwatch()..start();
    stats.receiveTime = Util.getTimeStamp();
    String chainJson = jsonEncode(versionChain);
    String encryptedChainJson = _encrypt!.encrypt(timestamp, chainJson);
    var rawResource = UnsignedResource(
      key: resourceKeyVersionTree,
      subKey: '',
      timestamp: timestamp,
      data: encryptedChainJson,
    );
    String signature = _genSignature(rawResource.getFeature());
    var cipherMessage = CipherMessage.fromRaw(rawResource, signature);

    List<CipherMessage> resourceList = [cipherMessage];
    String signatureOfList = _genSignature(CipherMessages.getFeature(resourceList));
    CipherMessages cipherMessages = CipherMessages(userPublicId: _signing!.getCompressedPublicKey(), resources: resourceList, signature: signatureOfList);
    String cipherMessagesJson = jsonEncode(cipherMessages);
    processingTimer.stop();
    stats.versionTreeCost += processingTimer.elapsedMilliseconds;
    _village?.sendVersionTree(cipherMessagesJson, stats);
  }

  void _onSendRequireVersions(List<String> versions, TimeCostStatistics stats) {
    final processingTimer = Stopwatch()..start();
    stats.receiveTime = Util.getTimeStamp();
    var requiredVersions = RequireVersions(requiredVersions: versions);
    String json = jsonEncode(requiredVersions);
    String signature = _genSignature(json);
    UncipherMessage uncipherMessage = UncipherMessage(userPublicId: _signing!.getCompressedPublicKey(), data: json, signature: signature);
    String uncipherMessageJson = jsonEncode(uncipherMessage);
    processingTimer.stop();
    stats.requiredVersionsCost += processingTimer.elapsedMilliseconds;
    _village?.sendRequireVersions(uncipherMessageJson, stats);
  }

  void _onSendVersions(List<SendVersions> versions, TimeCostStatistics stats) {
    final processingTimer = Stopwatch()..start();
    stats.receiveTime = Util.getTimeStamp();
    List<CipherMessage> resourceList = [];
    for(var version in versions) {
      String encryptedContent = _encrypt!.encrypt(version.createdAt, version.versionContent);
      UnsignedResource unsignedResource = UnsignedResource(
        key: version.versionHash,
        subKey: '',
        timestamp: version.createdAt,
        data: encryptedContent,
      );
      String signature = _genSignature(unsignedResource.getFeature());
      CipherMessage cipherMessage = CipherMessage.fromRaw(unsignedResource, signature);

      resourceList.add(cipherMessage);

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
        CipherMessage cipherObject = CipherMessage.fromRaw(rawObject, signature);

        resourceList.add(cipherObject);
      }
    }
    String signature = _genSignature(CipherMessages.getFeature(resourceList));
    final cipherMessages = CipherMessages(userPublicId: _signing!.getCompressedPublicKey(), resources: resourceList, signature: signature);
    String json = jsonEncode(cipherMessages);

    processingTimer.stop();
    stats.versionCost += processingTimer.elapsedMilliseconds;
    _village?.sendVersions(json, stats);
  }

  void _onNewNodeDiscovered(String host, int port, String deviceId) {
    MyLogger.info('New node detected: $host:$port, deviceId=$deviceId');
    _village?.newNodeDiscovered(host, port, deviceId);
  }

  String _genSignature(String text) {
    return _signing!.sign(HashUtil.hashText(text));
  }
  bool _verifySignature(String text, String stringSignature) {
    return _verify!.ver(HashUtil.hashText(text), stringSignature);
  }

  void _onReceivedOffer(String senderPublicKey, String data, TimeCostStatistics stats) {
    try {
      UncipherMessage uncipherMessage = UncipherMessage.fromJson(jsonDecode(data));
      final serverPublicKey = uncipherMessage.userPublicId;
      if(serverPublicKey != senderPublicKey) {
        MyLogger.info('Receive OFFER message not signed by its sender');
        return;
      }
      if(!_verifySignatureWithKey(serverPublicKey, uncipherMessage.data, uncipherMessage.signature)) {
        MyLogger.info('Verify OFFER message signature failed');
        return;
      }
      final offer = Offer.fromJson(jsonDecode(uncipherMessage.data));
      if(offer.type != offerTypeStorage) {
        MyLogger.info('Ignore unsupported OFFER type: ${offer.type}');
        return;
      }
      if(offer.target != _signing!.getCompressedPublicKey()) {
        MyLogger.info('Ignore OFFER for another target: ${offer.target}');
        return;
      }
      stats.transportTime = Util.getTimeStamp();
      _sendPort.send(Message(
        cmd: Command.receiveOffer,
        parameter: uncipherMessage,
        stats: stats,
      ));
    } catch(e) {
      MyLogger.warn('Failed to handle OFFER: $e');
    }
  }

  void _onReceivedApply(String senderPublicKey, String data, TimeCostStatistics stats) {
    // 7) handle storage apply (normally server handles this, but verify signature for completeness)
    try {
      UncipherMessage uncipherMessage = UncipherMessage.fromJson(jsonDecode(data));
      final clientPublicKey = uncipherMessage.userPublicId;
      if(clientPublicKey != senderPublicKey) {
        MyLogger.info('Receive APPLY message not signed by its sender');
        return;
      }
      if(!_verifySignatureWithKey(clientPublicKey, uncipherMessage.data, uncipherMessage.signature)) {
        MyLogger.info('Verify APPLY message signature failed');
        return;
      }
      MyLogger.info('Receive APPLY message from client: $clientPublicKey. Only handle it in server mode, ignore it in app mode');
      return;
    } catch(e) {
      MyLogger.warn('Failed to handle APPLY: $e');
    }
  }

  void _onSendApply(String applyDataStr, TimeCostStatistics stats) {
    stats.receiveTime = Util.getTimeStamp();
    String signature = _genSignature(applyDataStr);
    UncipherMessage uncipherMessage = UncipherMessage(
      userPublicId: _signing!.getCompressedPublicKey(),
      data: applyDataStr,
      signature: signature,
    );
    String uncipherMessageJson = jsonEncode(uncipherMessage);
    _village?.sendApply(uncipherMessageJson, stats);
  }

  bool _verifySignatureWithKey(String publicKey, String data, String signature) {
    try {
      var verifier = _verifyMap[publicKey];
      if(verifier == null) {
        verifier = VerifyingWrapper.loadKey(publicKey);
        _verifyMap[publicKey] = verifier;
      }
      return verifier.ver(HashUtil.hashText(data), signature);
    } catch(e) {
      MyLogger.warn('Failed to verify signature with key $publicKey: $e');
      return false;
    }
  }
}
