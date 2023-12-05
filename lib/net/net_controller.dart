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
  Completer<bool>? finished;

  NetworkController(Isolate isolate, ReceivePort port): _isolate = isolate, _receivePort = port;

  void start(Setting settings, String deviceId, String privateKey) {
    MyLogger.info('Spawning isolate and start listening');
    _signing = SigningWrapper.loadKey(privateKey);
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

  void sendNewVersionTree(List<VersionData> versionData) {
    var dag = _buildDag(versionData);
    VersionChain versionChain = VersionChain(
      versionDag: dag,
    );
    String json = jsonEncode(versionChain);
    _sendPort?.send(Message(cmd: Command.sendVersionTree, parameter: json));
  }

  void sendRequireVersions(List<String> versions) {
    var requiredVersions = RequireVersions(requiredVersions: versions);
    String json = jsonEncode(requiredVersions);
    _sendPort?.send(Message(cmd: Command.sendRequireVersions, parameter: json));
  }

  void sendVersions(List<SendVersionsNode> versions) {
    var sendVersions = SendVersions(versions: versions);
    String json = jsonEncode(sendVersions);
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
      case Command.receiveVersionTree:
        final data = msg.parameter as List<VersionNode>;
        Controller.instance.receiveVersionTree(data);
        break;
      case Command.receiveRequiredVersions:
        final data = msg.parameter as List<String>;
        Controller.instance.receiveRequireVersions(data);
        break;
      case Command.receiveVersions:
        final data = msg.parameter as List<SendVersionsNode>;
        Controller.instance.receiveVersions(data);
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