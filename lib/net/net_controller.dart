/// Run in main isolate
/// Contact with net_isolate using isolate port

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/document/dal/doc_data.dart';
import 'package:my_log/my_log.dart';
import '../mindeditor/controller/callback_registry.dart';
import '../mindeditor/setting/constants.dart';
import '../mindeditor/setting/setting.dart';
import 'command.dart';
import 'status.dart';

class NetworkController {
  final Isolate _isolate;
  final ReceivePort _receivePort;
  SendPort? _sendPort;
  NetworkStatus _networkStatus = NetworkStatus.unknown;
  final Map<String, NodeInfo> _nodes = {};
  late SigningWrapper _signing;
  late VerifyingWrapper _verify;
  late EncryptWrapper _encrypt;
  Completer<bool>? finished;

  NetworkController(Isolate isolate, ReceivePort port): _isolate = isolate, _receivePort = port;

  void start(Setting settings, String deviceId, String privateKey) {
    MyLogger.info('Spawning isolate and start listening');
    _signing = SigningWrapper.loadKey(privateKey);
    _verify = VerifyingWrapper.loadKey(_signing.getCompressedPublicKey());
    _encrypt = EncryptWrapper(key: _signing.key);
    final serverList = settings.getSetting(Constants.settingKeyServerList)?? Constants.settingDefaultServerList;
    final localPort = settings.getSetting(Constants.settingKeyLocalPort)?? Constants.settingDefaultLocalPort;
    _receivePort.listen((data) {
      if(data is SendPort) {
        MyLogger.info('Get SendPort from network isolate, start village protocol');
        _sendPort = data;
        _gracefulStartVillage(localPort, serverList, deviceId);
      } else if(data is Message) {
        if(_sendPort != null) {
          _onMessage(data);
        }
      }
    });
  }

  /// Pack versionData in VersionChain, encrypt it, and sign it
  void sendNewVersionTree(List<VersionData> versionData, int timestamp) {
    //TODO better to move encryption and signing to Village isolate
    var dag = _buildDag(versionData);
    VersionChain versionChain = VersionChain(
      versionDag: dag,
    );
    String chainJson = jsonEncode(versionChain);
    String encryptedChainJson = _encrypt.encrypt(timestamp, chainJson);
    var rawResource = UnsignedResource(
      key: Constants.resourceKeyVersionTree,
      subKey: '',
      timestamp: timestamp,
      data: encryptedChainJson,
    );
    String signature = _signing.sign(rawResource.getFeature());
    var signedResource = SignedResource.fromRaw(rawResource, signature);

    List<SignedResource> resourceList = [signedResource];
    String signatureOfList = _signing.sign(SignedResources.getFeature(resourceList));
    SignedResources signedResources = SignedResources(userPublicId: _signing.getCompressedPublicKey(), resources: resourceList, signature: signatureOfList);
    String signedResourcesJson = jsonEncode(signedResources);
    _sendPort?.send(Message(cmd: Command.sendVersionTree, parameter: signedResourcesJson));
  }

  void sendRequireVersions(List<String> versions) {
    var requiredVersions = RequireVersions(requiredVersions: versions);
    String json = jsonEncode(requiredVersions);
    String signature = _signing.sign(json);
    SignedMessage signedMessage = SignedMessage(userPublicId: _signing.getCompressedPublicKey(), data: json, signature: signature);
    String signedMessageJson = jsonEncode(signedMessage);
    _sendPort?.send(Message(cmd: Command.sendRequireVersions, parameter: signedMessageJson));
  }

  void sendVersions(List<SendVersionsNode> versions) {
    List<SignedResource> resourceList = [];
    for(var version in versions) {
      int timestamp = version.createdAt;
      String encryptedContent = _encrypt.encrypt(timestamp, version.versionContent);
      UnsignedResource unsignedResource = UnsignedResource(
        key: version.versionHash,
        subKey: '',
        timestamp: timestamp,
        data: encryptedContent,
      );
      String signature = _signing.sign(unsignedResource.getFeature());
      SignedResource signedResource = SignedResource.fromRaw(unsignedResource, signature);

      resourceList.add(signedResource);

      for(var item in version.requiredObjects.entries) {
        String hash = item.key;
        var (timestamp, value) = item.value;
        String encryptedContent = _encrypt.encrypt(timestamp, value);
        UnsignedResource rawObject = UnsignedResource(
          key: hash,
          subKey: '',
          timestamp: timestamp,
          data: encryptedContent,
        );
        String signature = _signing.sign(rawObject.getFeature());
        SignedResource signedObject = SignedResource.fromRaw(rawObject, signature);

        resourceList.add(signedObject);
      }
    }
    String signature = _signing.sign(SignedResources.getFeature(resourceList));
    final signedResources = SignedResources(userPublicId: _signing.getCompressedPublicKey(), resources: resourceList, signature: signature);
    String json = jsonEncode(signedResources);
    _sendPort?.send(Message(cmd: Command.sendVersions, parameter: json));
  }
  
  Completer<bool> gracefulTerminate() {
    _sendPort?.send(Message(cmd: Command.terminate, parameter: null));
    finished = Completer();
    return finished!;
  }

  NetworkStatus getNetworkStatus() {
    return _networkStatus;
  }

  List<NodeInfo> getNetworkDetails() {
    return _nodes.values.toList();
  }

  void _onMessage(Message msg) {
    switch(msg.cmd) {
      case Command.terminate:
      case Command.startVillage:
      case Command.sendVersionTree:
      case Command.sendRequireVersions:
      case Command.sendVersions:
        // Do nothing, these parts are in net_isolate
        break;
      case Command.terminateOk:
        _receivePort.close();
        _isolate.kill();
        finished?.complete(true);
        break;
      case Command.networkStatus:
        if(msg.parameter is NetworkStatus) {
          if(_networkStatus != msg.parameter) {
            _networkStatus = msg.parameter;
            CallbackRegistry.triggerNetworkStatusChanged(msg.parameter);
          }
        }
        break;
      case Command.nodeStatus:
        if(msg.parameter is List<NodeInfo>) {
          var list = msg.parameter as List<NodeInfo>;
          MyLogger.info('Get node list: $list');
          for(final item in list) {
            final id = item.id;
            _nodes[id] = item;
          }
        }
        break;
      case Command.receiveProvide:
        /// 1. Check public key is the same
        /// 2. Verify message and every single resource
        /// 3. Decrypt resources
        /// 4. notify upper layer
        final data = msg.parameter as String;
        final signedResources = SignedResources.fromJson(jsonDecode(data));
        final publicKey = signedResources.userPublicId;
        if(publicKey != _signing.getCompressedPublicKey()) {
          MyLogger.info('Receive provide message from other user: $publicKey');
          break;
        }
        String feature = SignedResources.getFeature(signedResources.resources);
        final ok = _verify.ver(feature, signedResources.signature);
        if(!ok) {
          MyLogger.info('Verify provide message failed');
          break;
        }
        List<UnsignedResource> unsignedResourceList = [];
        for(var resource in signedResources.resources) {
          UnsignedResource rawResource = UnsignedResource(
            key: resource.key,
            subKey: resource.subKey,
            timestamp: resource.timestamp,
            data: resource.data,
          );
          if(!_verify.ver(rawResource.getFeature(), resource.signature)) {
            continue;
          }
          var plainText = _encrypt.decrypt(rawResource.timestamp, rawResource.data);
          rawResource.data = plainText;
          unsignedResourceList.add(rawResource);
        }
        Controller.instance.receiveResources(unsignedResourceList);
        break;
      case Command.receiveQuery:
        /// 1. Check public key is the same
        /// 2. Verify message
        /// 3. notify upper layer
        final data = msg.parameter as String;
        SignedMessage signedMessage = SignedMessage.fromJson(jsonDecode(data));
        final publicKey = signedMessage.userPublicId;
        if(publicKey != _signing.getCompressedPublicKey()) {
          MyLogger.info('Receive verify message from other user: $publicKey');
          break;
        }
        if(!_verify.ver(signedMessage.data, signedMessage.signature)) {
          MyLogger.info('Verify query message failed');
          break;
        }
        var requiredVersions = RequireVersions.fromJson(jsonDecode(signedMessage.data));
        Controller.instance.receiveRequireVersions(requiredVersions.requiredVersions);
        break;
    }
  }

  void _gracefulStartVillage(String localPort, String serverList, String deviceId) {
    _sendPort?.send(Message(
      cmd: Command.startVillage,
      parameter: StartVillageParameter(
        localPort: localPort,
        serverList: serverList,
        deviceId: deviceId,
      ),
    ));
  }

  List<VersionNode> _buildDag(List<VersionData> data) {
    List<VersionNode> result = [];
    for(var item in data) {
      String versionHash = item.versionHash;
      var parents = item.parents.split(',');
      final timestamp = item.createdAt;
      var node = VersionNode(versionHash: versionHash, createdAt: timestamp, parents: parents);
      result.add(node);
    }
    return result;
  }
}