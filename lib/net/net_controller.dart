/// Run in main isolate
/// Contact with net_isolate using isolate port

import 'dart:async';
import 'dart:isolate';
import 'package:bonsoir/bonsoir.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/document/dal/doc_data_model.dart';
import 'package:my_log/my_log.dart';
import '../mindeditor/controller/callback_registry.dart';
import '../mindeditor/setting/constants.dart';
import '../mindeditor/setting/setting.dart';
import 'command.dart';
import 'status.dart';
import 'version_chain_api.dart';

class NetworkController {
  static const _bonjourName = 'VillageProtocol';
  static const _bonjourType = '_village-v0._udp';
  BonsoirBroadcast? _bonjourBroadcast;
  BonsoirDiscovery? _bonjourDiscovery;
  final Isolate _isolate;
  final ReceivePort _receivePort;
  SendPort? _sendPort;
  NetworkStatus _networkStatus = NetworkStatus.unknown;
  final Map<String, NodeInfo> _nodes = {};
  Completer<bool>? finished;
  late int _servicePort;
  late String _deviceId;

  NetworkController(Isolate isolate, ReceivePort port): _isolate = isolate, _receivePort = port;

  void start(Setting settings, String deviceId, UserPrivateInfo userPrivateInfo, String? logPath) {
    if(isStarted()) return;

    MyLogger.info('Spawning isolate and start listening');
    final rawServerList = settings.getSetting(Constants.settingKeyServerList)?? Constants.settingDefaultServerList;
    final cleanedServerList = rawServerList.replaceAll('，', ',').replaceAll('：', ':');
    final localPort = settings.getSetting(Constants.settingKeyLocalPort)?? Constants.settingDefaultLocalPort;
    _servicePort = int.parse(localPort);
    _deviceId = deviceId;
    _networkStatus = NetworkStatus.starting;
    bool useBonjour = true;
    final useMulticast = !useBonjour;
    _receivePort.listen((data) {
      if(data is SendPort) {
        MyLogger.info('Get SendPort from network isolate, start village protocol, using Bonjour=$useBonjour');
        _sendPort = data;
        _gracefulStartVillage(localPort, cleanedServerList, deviceId, userPrivateInfo, useMulticast, logPath);
      } else if(data is Message) {
        if(_sendPort != null) {
          _onMessage(data);
        }
      }
    });
    if(useBonjour) {
      _startBonjour();
    }
  }

  void sendVersionBroadcast(String latestVersion) {
    var msg = BroadcastMessages(
      messages: {
        'latest_version': latestVersion,
      }
    );
    _sendPort?.send(
      Message(
        cmd: Command.sendBroadcast,
        parameter: msg,
      ),
    );
  }
  /// Pack versionData in VersionChain, encrypt it, and sign it
  void sendNewVersionTree(List<VersionDataModel> versionData, int timestamp) {
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

  void sendRequireVersionTree(String latestVersion) {
    // Reuse require versions message
    sendRequireVersions([latestVersion]);
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

    _bonjourBroadcast?.stop();
    _bonjourDiscovery?.stop();
    finished = Completer();
    _sendPort?.send(Message(cmd: Command.terminate, parameter: null));
    return finished!;
  }

  bool isStarted() => _networkStatus != NetworkStatus.unknown;

  NetworkStatus getNetworkStatus() {
    return _networkStatus;
  }
  bool isAlone() {
    if(_networkStatus != NetworkStatus.running) {
      return true;
    }
    for(final node in _nodes.values) {
      if(node.status == NodeStatus.inContact) {
        return false;
      }
    }
    return true;
  }

  List<NodeInfo> getNetworkDetails() {
    return _nodes.values.toList();
  }

  void _updateNodeList(List<NodeInfo> list) {
    for(final item in list) {
      final id = item.peer;
      _nodes[id] = item;
    }
    CallbackRegistry.triggerPeerNodesChanged(_nodes);
  }

  void _onMessage(Message msg) {
    final controller = Controller();
    switch(msg.cmd) {
      case Command.terminate:
      case Command.startVillage:
      case Command.newNodeDiscovered:
      case Command.sendBroadcast:
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
          _updateNodeList(list);
        }
        break;
      case Command.receiveBroadcast:
        final param = msg.parameter as BroadcastMessages;
        final latestVersion = param.messages['latest_version'];
        if(latestVersion != null) {
          controller.receiveVersionBroadcast(latestVersion);
        }
        break;
      case Command.receiveProvide:
        final param = msg.parameter as ReceiveProvideParameter;
        controller.receiveResources(param.resources);
        break;
      case Command.receiveQuery:
        final param = msg.parameter as ReceiveQueryParameter;
        controller.receiveRequireVersions(param.requiredObjects);
        break;
    }
  }

  void _gracefulStartVillage(String localPort, String serverList, String deviceId, UserPrivateInfo userPrivateInfo, bool useMulticast, String? logPath) {
    _sendPort?.send(Message(
      cmd: Command.startVillage,
      parameter: StartVillageParameter(
        localPort: localPort,
        serverList: serverList,
        deviceId: deviceId,
        userInfo: userPrivateInfo,
        useMulticast: useMulticast,
        logPath: logPath,
      ),
    ));
  }

  List<VersionNode> _buildDag(List<VersionDataModel> data) {
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

  Future<void> _startBonjour() async {
    _startBonjourBroadcast();
    _startBonjourDiscovery();
  }
  Future<void> _startBonjourBroadcast() async {
    BonsoirService service = BonsoirService(
      name: _bonjourName,
      type: _bonjourType,
      port: _servicePort,
      attributes: {
        'device': _deviceId,
      },
    );

    // And now we can broadcast it :
    BonsoirBroadcast broadcast = BonsoirBroadcast(service: service);
    await broadcast.ready;
    await broadcast.start();
    _bonjourBroadcast = broadcast;
  }
  Future<void> _startBonjourDiscovery() async {
    BonsoirDiscovery discovery = BonsoirDiscovery(type: _bonjourType);
    await discovery.ready;

    discovery.eventStream!.listen((event) {
      // `eventStream` is not null as the discovery instance is "ready" !
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
        MyLogger.info('Bonjour service found : ${event.service?.toJson()}');
        event.service!.resolve(discovery.serviceResolver); // Should be called when the user wants to connect to this service.
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
        MyLogger.info('Bonjour service resolved : ${event.service?.toJson()}');
        final service = event.service as ResolvedBonsoirService?;
        if(service == null) return;

        final host = service.host; // May be the host name, should be resolved to ip address
        final port = service.port;
        final attributes = service.attributes;
        final deviceId = attributes['device'];
        if(host == null || deviceId == null) return;
        MyLogger.info('Bonjour node resolved: $host:$port, deviceId=$deviceId, current deviceId=$_deviceId');
        if(deviceId == _deviceId) return; // Ignore self

        _onDiscoverNewNode(host, port, deviceId);
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
        MyLogger.info('Bonjour service lost : ${event.service?.toJson()}');
      }
    });
    // Start the discovery **after** listening to discovery events :
    await discovery.start();
    _bonjourDiscovery = discovery;
  }

  void _onDiscoverNewNode(String host, int port, String deviceId) {
    MyLogger.info('Bonjour node discovered: $host:$port, deviceId=$deviceId');
    _sendPort?.send(Message(
      cmd: Command.newNodeDiscovered,
      parameter: NewNodeDiscoveredParameter(
        host: host,
        port: port,
        deviceId: deviceId,
      ),
    ));
  }
}