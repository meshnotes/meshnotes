/// Run in a separated isolate

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:mesh_note/net/version_chain_api.dart';
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
        _sendPort.send(Message(cmd: Command.terminateOk, parameter: null));
        break;
      case Command.startVillage:
        if(_village != null) {
          return;
        }
        if(msg.parameter == null || msg.parameter is! StartVillageParameter) {
          return;
        }
        final parameter = msg.parameter as StartVillageParameter;
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
        ;
        _village = await startVillage(
          parameter.localPort,
          parameter.serverList,
          parameter.deviceId,
          UserPublicInfo(publicKey: userPrivateInfo!.publicKey, userName: userPrivateInfo!.userName, timestamp: userPrivateInfo!.timestamp),
          _nodeChanged,
          handler,
        );
        _sendPort.send(Message(cmd: Command.networkStatus, parameter: NetworkStatus.running,));
        break;
      case Command.terminateOk:
      case Command.networkStatus:
      case Command.nodeStatus:
      case Command.receiveProvide:
      case Command.receiveQuery:
      // Do nothing, these commands are handled in net_controller
        break;
      case Command.sendVersionTree:
        final param = msg.parameter as SendVersionTreeParameter;
        _onSendVersionTree(param.versionChain, param.timestamp);
        break;
      case Command.sendRequireVersions:
        final param = msg.parameter as SendRequireVersionsParameter;
        _onSendRequireVersions(param.versions);
        break;
      case Command.sendVersions:
        final sendVersions = msg.parameter as SendVersionsParameter;
        _onSendVersions(sendVersions.versions);
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
    final device = node.id;
    final nodeInfo = NodeInfo(peer: id, device: device, name: info, status: _status);
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
    _sendPort.send(Message(
      cmd: Command.nodeStatus,
      parameter: nodeList,
    ));
    _nodes.clear();
  }

  void _handleProvide(String data) {
    /// 1. Check public key is the same
    /// 2. Verify message and every single resource
    /// 3. Decrypt resources
    /// 4. Send to port to notify upper layer
    final signedResources = SignedResources.fromJson(jsonDecode(data));
    final publicKey = signedResources.userPublicId;
    if(publicKey != _signing!.getCompressedPublicKey()) {
      MyLogger.info('Receive provide message from other user: $publicKey');
      return;
    }
    String feature = SignedResources.getFeature(signedResources.resources);
    final ok = _verify!.ver(feature, signedResources.signature);
    if(!ok) {
      MyLogger.info('Verify provide message failed');
      return;
    }
    List<UnsignedResource> unsignedResourceList = [];
    for(var resource in signedResources.resources) {
      UnsignedResource rawResource = UnsignedResource(
        key: resource.key,
        subKey: resource.subKey,
        timestamp: resource.timestamp,
        data: resource.data,
      );
      if(!_verify!.ver(rawResource.getFeature(), resource.signature)) {
        continue;
      }
      var plainText = _encrypt!.decrypt(rawResource.timestamp, rawResource.data);
      rawResource.data = plainText;
      unsignedResourceList.add(rawResource);
    }
    _sendPort.send(Message(
      cmd: Command.receiveProvide,
      parameter: ReceiveProvideParameter(
        resources: unsignedResourceList,
      ),
    ));
  }

  void _handleQuery(String data) {
    /// 1. Check public key is the same
    /// 2. Verify message
    /// 3. Send to port to notify upper layer
    SignedMessage signedMessage = SignedMessage.fromJson(jsonDecode(data));
    final publicKey = signedMessage.userPublicId;
    if(publicKey != _signing!.getCompressedPublicKey()) {
      MyLogger.info('Receive verify message from other user: $publicKey');
      return;
    }
    if(!_verify!.ver(signedMessage.data, signedMessage.signature)) {
      MyLogger.info('Verify query message failed');
      return;
    }
    var requiredVersions = RequireVersions.fromJson(jsonDecode(signedMessage.data));
    _sendPort.send(Message(
      cmd: Command.receiveQuery,
      parameter: ReceiveQueryParameter(
        requiredObjects: requiredVersions.requiredVersions,
      ),
    ));
  }

  void _onSendVersionTree(VersionChain versionChain, int timestamp) {
    String chainJson = jsonEncode(versionChain);
    String encryptedChainJson = _encrypt!.encrypt(timestamp, chainJson);
    var rawResource = UnsignedResource(
      key: Constants.resourceKeyVersionTree,
      subKey: '',
      timestamp: timestamp,
      data: encryptedChainJson,
    );
    String signature = _signing!.sign(rawResource.getFeature());
    var signedResource = SignedResource.fromRaw(rawResource, signature);

    List<SignedResource> resourceList = [signedResource];
    String signatureOfList = _signing!.sign(SignedResources.getFeature(resourceList));
    SignedResources signedResources = SignedResources(userPublicId: _signing!.getCompressedPublicKey(), resources: resourceList, signature: signatureOfList);
    String signedResourcesJson = jsonEncode(signedResources);
    _village?.sendVersionTree(signedResourcesJson);
  }

  void _onSendRequireVersions(List<String> versions) {
    var requiredVersions = RequireVersions(requiredVersions: versions);
    String json = jsonEncode(requiredVersions);
    String signature = _signing!.sign(json);
    SignedMessage signedMessage = SignedMessage(userPublicId: _signing!.getCompressedPublicKey(), data: json, signature: signature);
    String signedMessageJson = jsonEncode(signedMessage);
    _village?.sendRequireVersions(signedMessageJson);
  }

  void _onSendVersions(List<SendVersions> versions) {
    List<SignedResource> resourceList = [];
    for(var version in versions) {
      String encryptedContent = _encrypt!.encrypt(version.createdAt, version.versionContent);
      UnsignedResource unsignedResource = UnsignedResource(
        key: version.versionHash,
        subKey: '',
        timestamp: version.createdAt,
        data: encryptedContent,
      );
      String signature = _signing!.sign(unsignedResource.getFeature());
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
        String signature = _signing!.sign(rawObject.getFeature());
        SignedResource signedObject = SignedResource.fromRaw(rawObject, signature);

        resourceList.add(signedObject);
      }
    }
    String signature = _signing!.sign(SignedResources.getFeature(resourceList));
    final signedResources = SignedResources(userPublicId: _signing!.getCompressedPublicKey(), resources: resourceList, signature: signature);
    String json = jsonEncode(signedResources);

    _village?.sendVersions(json);
  }
}