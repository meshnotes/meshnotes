/// Run in a separated isolate

import 'dart:async';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:my_log/my_log.dart';
import 'p2p_net.dart';
import 'package:libp2p/application/application_layer.dart';
import 'command.dart';
import 'status.dart';

Village? _village;
SendPort? _sendPort;
Timer? _timer;

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
  // Exchange communication port
  var receivePort = ReceivePort();
  MyLogger.info('Sending SendPort to main isolate');
  _data.sendPort.send(receivePort.sendPort);
  _sendPort = _data.sendPort;

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
      _sendPort?.send(Message(cmd: Command.terminateOk, parameter: null));
      break;
    case Command.startVillage:
      if(_village != null) {
        return;
      }
      if(msg.parameter == null || msg.parameter is! StartVillageParameter) {
        return;
      }
      final parameter = msg.parameter as StartVillageParameter;
      VillageMessageHandler handler = VillageMessageHandler()
        ..handleNewVersionTree = _handleNewVersionTree
        ..handleRequireVersions = _handleRequireVersions
        ..handleSendVersions = _handleSendVersions;
      _village = await startVillage(parameter.localPort, parameter.serverList, parameter.deviceId, _nodeChanged, handler);
      _sendPort?.send(Message(cmd: Command.networkStatus, parameter: NetworkStatus.running,));
      break;
    case Command.terminateOk:
    case Command.networkStatus:
    case Command.nodeStatus:
    case Command.receiveVersionTree:
    case Command.receiveRequiredVersions:
    case Command.receiveVersions:
      // Do nothing, these part is in net_controller
      break;
    case Command.sendVersionTree:
      final versionTreeJson = msg.parameter as String;
      _village?.sendVersionTree(versionTreeJson);
      break;
    case Command.sendRequireVersions:
      final requiredVersions = msg.parameter as String;
      _village?.sendRequireVersions(requiredVersions);
      break;
    case Command.sendVersions:
      //TODO implement it
      final sendVersions = msg.parameter as String;
      _village?.sendVersions(sendVersions);
      break;
  }
}

Map<String, NodeInfo> _nodes = {};
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
  final info = node.id;
  final nodeInfo = NodeInfo(id: id, name: info, status: _status);
  _nodes[id] = nodeInfo;
  MyLogger.info('Node changed: $id: $nodeInfo');
}
void _handleNewVersionTree(List<VersionNode> dag) {
  _sendPort?.send(Message(
    cmd: Command.receiveVersionTree,
    parameter: dag,
  ));
}
void _handleRequireVersions(List<String> requiredVersions) {
  _sendPort?.send(Message(
    cmd: Command.receiveRequiredVersions,
    parameter: requiredVersions,
  ));
}
void _handleSendVersions(List<SendVersionsNode> versions) {
  _sendPort?.send(Message(
    cmd: Command.receiveVersions,
    parameter: versions,
  ));
}

void _timerHandler(Timer _t) {
  if(_nodes.isEmpty) return;

  final nodeList = _nodes.values.toList();
  _sendPort?.send(Message(
    cmd: Command.nodeStatus,
    parameter: nodeList,
  ));
  _nodes.clear();
}