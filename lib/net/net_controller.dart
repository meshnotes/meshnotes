/// Run in main isolate
/// Contact with net_isolate using isolate port

import 'dart:async';
import 'dart:isolate';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/document/dal/doc_data.dart';
import 'package:my_log/my_log.dart';
import '../mindeditor/controller/callback_registry.dart';
import '../mindeditor/setting/constants.dart';
import '../mindeditor/setting/setting.dart';
import 'command.dart';
import 'status.dart';
import 'version_chain_api.dart';

class NetworkController {
  final Isolate _isolate;
  final ReceivePort _receivePort;
  SendPort? _sendPort;
  NetworkStatus _networkStatus = NetworkStatus.unknown;
  final Map<String, NodeInfo> _nodes = {};
  Completer<bool>? finished;

  NetworkController(Isolate isolate, ReceivePort port): _isolate = isolate, _receivePort = port;

  void start(Setting settings, String deviceId, UserPrivateInfo userPrivateInfo) {
    if(isStarted()) return;

    MyLogger.info('Spawning isolate and start listening');
    final serverList = settings.getSetting(Constants.settingKeyServerList)?? Constants.settingDefaultServerList;
    final localPort = settings.getSetting(Constants.settingKeyLocalPort)?? Constants.settingDefaultLocalPort;
    _networkStatus = NetworkStatus.starting;
    _receivePort.listen((data) {
      if(data is SendPort) {
        MyLogger.info('Get SendPort from network isolate, start village protocol');
        _sendPort = data;
        _gracefulStartVillage(localPort, serverList, deviceId, userPrivateInfo);
      } else if(data is Message) {
        if(_sendPort != null) {
          _onMessage(data);
        }
      }
    });
  }

  /// Pack versionData in VersionChain, encrypt it, and sign it
  void sendNewVersionTree(List<VersionData> versionData, int timestamp) {
    if(!isStarted()) return;
    var dag = _buildDag(versionData);
    VersionChain versionChain = VersionChain(
      versionDag: dag,
    );
    _sendPort?.send(
      Message(
        cmd: Command.sendVersionTree,
        parameter: SendVersionTreeParameter(
          versionChain: versionChain,
          timestamp: timestamp,
        )
      )
    );
  }

  void sendRequireVersions(List<String> versions) {
    if(!isStarted()) return;
    _sendPort?.send(
      Message(
        cmd: Command.sendRequireVersions,
        parameter: SendRequireVersionsParameter(
          versions: versions,
        )
      )
    );
  }

  void sendVersions(List<SendVersions> versions) {
    if(!isStarted()) return;
    _sendPort?.send(
      Message(
        cmd: Command.sendVersions,
        parameter: SendVersionsParameter(
          versions: versions,
        ),
      )
    );
  }
  
  Completer<bool>? gracefulTerminate() {
    if(!isStarted()) return null;
    finished = Completer();
    _sendPort?.send(Message(cmd: Command.terminate, parameter: null));
    return finished!;
  }

  NetworkStatus getNetworkStatus() {
    return _networkStatus;
  }

  List<NodeInfo> getNetworkDetails() {
    return _nodes.values.toList();
  }

  bool isStarted() => _networkStatus != NetworkStatus.unknown;

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
            final id = item.peer;
            _nodes[id] = item;
          }
        }
        break;
      case Command.receiveProvide:
        final param = msg.parameter as ReceiveProvideParameter;
        Controller.instance.receiveResources(param.resources);
        break;
      case Command.receiveQuery:
        final param = msg.parameter as ReceiveQueryParameter;
        Controller.instance.receiveRequireVersions(param.requiredObjects);
        break;
    }
  }

  void _gracefulStartVillage(String localPort, String serverList, String deviceId, UserPrivateInfo userPrivateInfo) {
    _sendPort?.send(Message(
      cmd: Command.startVillage,
      parameter: StartVillageParameter(
        localPort: localPort,
        serverList: serverList,
        deviceId: deviceId,
        userInfo: userPrivateInfo,
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