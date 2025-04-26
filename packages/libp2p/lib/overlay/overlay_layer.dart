import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/network/network_env.dart';
import 'package:libp2p/overlay/overlay_msg.dart';
import 'package:libp2p/utils.dart';
import 'package:my_log/my_log.dart';
import 'package:libp2p/network/network_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import '../network/peer.dart';
import 'overlay_api.dart';
import 'overlay_controller.dart';

class VillageOverlay implements ApplicationController {
  static const __villageTimerInterval = 5000;
  static const logPrefix = '[Overlay]';
  static const _appName = 'overlay';
  // Network properties
  // List<String> sponsors;
  String _deviceId = '';
  int _localPort;
  final bool useMulticast;
  UserPublicInfo userInfo;
  SOTPNetworkLayer? __network;
  SOTPNetworkLayer get _network => __network!;
  ApplicationController? _defaultApp;
  Map<String, ApplicationController> _keyToApp = {};
  NetworkEnvSimulator? _networkEnvSimulator;

  // Villager node properties
  List<VillagerNode> _villagers = [];
  // TaskQueue _taskQueue = TaskQueue();

  // Callback function(s)
  OnNodeChangedCallbackType onNodeChanged;

  VillageOverlay({
    required this.userInfo,
    required List<String> sponsors,
    required this.onNodeChanged,
    String deviceId = '',
    int port = 0,
    this.useMulticast = false,
  }): _localPort = port, _deviceId = deviceId {
    registerApplication(_appName, this); // Make overlay itself as the first application

    MyLogger.info('${logPrefix} sponsors=$sponsors');
    // Add all sponsors to villagers list
    for(var sponsor in sponsors) {
      final sp = sponsor.split(':');
      if(sp.length != 2 || sp[0].isEmpty) {
        continue;
      }
      var host = sp[0];
      var port = int.tryParse(sp[1]);
      if(port == null) {
        port = 17974;
      }
      VillagerNode node = VillagerNode(host: host, port: port, isUpper: true);
      _addIntoVillagersIfNotExists(node);
    }
  }

  Future<void> start() async {
    if(__network != null) {
      __network!.stop();
    }
    InternetAddress localIp = InternetAddress.anyIPv4;
    __network = SOTPNetworkLayer(
      localIp: localIp,
      servicePort: _localPort,
      connectOkCallback: _onConnected,
      newConnectCallback: _onNewConnect,
      onDetected: _onDetected,
      deviceId: _deviceId,
      useMulticast: useMulticast,
      networkCondition: _networkEnvSimulator,
    );
    await _network.start();
    // Connect to upper nodes immediately
    _addConnectTasks(_villagers);
    Timer.periodic(Duration(milliseconds: __villageTimerInterval), _villageTimerHandler);
  }
  void stop() {
    _network.stop();
  }

  void setNetworkEnvSimulator(NetworkEnvSimulator? networkEnvSimulator) {
    _networkEnvSimulator = networkEnvSimulator;
  }

  /// @return true - success, false - failed
  bool registerApplication(String key, ApplicationController app, {bool setDefault=false}) {
    if(_keyToApp.containsKey(key)) { // Only the unregistered key could be registered successfully
      return false;
    }
    _keyToApp[key] = app;
    if(setDefault) {
      _defaultApp = app;
    }
    return true;
  }

  void sendData(String appKey, ApplicationController app, VillagerNode node, String type, String data) {
    ApplicationController? _checkedApp = _keyToApp[appKey];
    if(_checkedApp != app) {
      MyLogger.warn('${logPrefix} sendData: Application($_checkedApp) not compliance with key($appKey)');
      return;
    }

    final peer = node.getPeer();
    if(peer == null) return;

    final packData = AppData(appKey, type, data);
    final jsonStr = jsonEncode(packData);
    MyLogger.verbose('${logPrefix} Send message $jsonStr');
    peer.sendData(utf8.encode(jsonStr));
  }
  void sendToAllNodesOfUser(String appKey, ApplicationController app, String type, String data) {
    //TODO should change to only find the nodes with same user id(public key)
    final nodes = getAllNodes();
    MyLogger.info('${logPrefix} sendToAllNodesOfUser: find nodes: $nodes');
    for(var node in nodes) {
      MyLogger.info('${logPrefix} sendToAllNodesOfUser: send to node: $node, type: $type, data: ${data.substring(0, 100)}');
      sendData(appKey, app, node, type, data);
    }
  }

  @override
  void onData(VillagerNode node, String app, String type, String data) {
    MyLogger.debug('${logPrefix} Receive data($data) of app($app)/type($type) from node($node)');
    switch(type) {
      case overlayMessageTypeHello:
        _handleHelloMessage(node, data);
        break;
    }
  }

  void newNodeDiscovered(String host, int port, String deviceId) {
    MyLogger.info('${logPrefix} New node detected: $host:$port, deviceId=$deviceId');
    InternetAddress.lookup(host, type: InternetAddressType.IPv4) // Only IPv4 is supported
    .timeout(Duration(seconds: 30)) // Some xxx.local domain name may take a long time to resolve
    .then((values) {
      for(var ip in values) {
        if(ip.isLoopback) {
          MyLogger.info('${logPrefix} Ignore loopback address: $ip');
          continue; // Ignore loopback address
        }
        if(ip.type == InternetAddressType.IPv4) { 
          _onDetected(deviceId, ip, port);
          break;
        }
      }
    }).onError((error, stackTrace) {
      MyLogger.err('${logPrefix} Failed to resolve host($host): $error');
    });
  }

  void findTracker() {
    // TODO add findTracker task
  }
  void findMaster() {
    // TODO add findMaster task
  }

  void _villageTimerHandler(Timer _t) {
    _checkSponsors();
    _tryToReconnect();
  }

  void _addConnectTasks(List<VillagerNode> nodes) {
    // _taskQueue.enqueueAllWithType(TaskType.connect, _villagers);
    Future.delayed(Duration.zero, () {
      // final tasks = _taskQueue.popAllWithType(TaskType.connect);
      for(var v in nodes) {
        final status = v.getStatus();
        if(status == VillagerStatus.unknown) {
          _tryToResolve(v);
        } else if(status == VillagerStatus.resolved) {
          _tryToConnect(v);
        }
      }
    });
  }
  void _addHelloTask(VillagerNode node) {
    Future.delayed(Duration.zero, () {
      MyLogger.debug('${logPrefix} Send hello message to new node');
      sendData(_appName, this, node, overlayMessageTypeHello, _introduceMyselfMessage());
    });
  }

  void _onConnected(Peer _c) {
    VillagerNode? found;
    for(final node in _villagers) {
      if(node.getPeer() == _c) {
        found = node;
        break;
      }
    }
    if(found != null) {
      _onConnect(found);
    }
  }
  void _onNewConnect(Peer _c) {
    var host = _c.ip.address;
    var port = _c.port;
    VillagerNode? node = _findVillageByIpAndPort(_c.ip, _c.port);
    if(node != null) {
      final oldPeer = node.getPeer();
      // If already has a valid connection, do nothing
      if(oldPeer != null && oldPeer.getStatus() == ConnectionStatus.established) {
        return;
      }
    } else { // No node found, create a new one
      node = VillagerNode(host: host, port: port, isUpper: true)
        ..ip = _c.ip;
    }
    // When run here, the node is either not in _villagers list or has an invalid connection. So update it
    node.setPeer(_c);
    _c
      ..setOnReceive((data) {
        _onRawData(node!, data);
      })
      ..setOnDisconnect(_onDisconnect)
      ..setOnConnectFail(_onConnectionFail);
    _addIntoVillagersIfNotExists(node);
    _onConnect(node);
  }
  void _onDetected(String peerDeviceId, InternetAddress peerIp, int peerPort) {
    MyLogger.info('${logPrefix} Detected peer($peerDeviceId) with address(${peerIp.address}:$peerPort)');
    if(_alreadyInVillagers(peerIp, peerPort)) {
      return;
    }
    MyLogger.info('${logPrefix} Try to connect to new node(${peerIp.address}:$peerPort)');
    var node = VillagerNode(host: peerIp.address, port: peerPort)
      ..ip = peerIp;
    _addIntoVillagersIfNotExists(node);
    // // To avoid both peers detected each other and made duplicate connection, try to wait a random time
    // // If both peers still make connection at the same time, cancel one of them in a fixed strategy
    // Timer(Duration(milliseconds: randomInt(0, 5000)), () { // Wait from 0 to 5 seconds
    //   _tryToConnect(node);
    // });
  }
  void _onConnect(VillagerNode _node) {
    MyLogger.info('${logPrefix} New connection to address(${_node.ip}:${_node.port}), id=${_node.id}, say Hello');
    _node.setConnected();
    _addHelloTask(_node);
    onNodeChanged(_node);
  }
  void _onConnectionFail(Peer peer) {
    MyLogger.info('${logPrefix} connection failed');
    for(var node in _villagers) {
      if(node.getPeer() != peer) continue;

      if(node.isUpper) {
        node.setUnknown();
      } else {
        node.setUnknown();
        _villagers.remove(node);
      }
      onNodeChanged(node);
      break;
    }
  }
  void _onDisconnect(Peer peer) {
    MyLogger.info('${logPrefix} disconnected');
    for(var node in _villagers) {
      if(node.getPeer() != peer) continue;

      if(node.isUpper) {
        node.setLost();
      } else {
        node.setLost();
        _villagers.remove(node);
      }
      onNodeChanged(node);
      break;
    }
  }

  void _onRawData(VillagerNode node, List<int> rawData) {
    MyLogger.verbose('${logPrefix} Receive rawData: $rawData on node($node)');
    final str = utf8.decode(rawData);
    Map<String, dynamic> jsonMap = jsonDecode(str);
    AppData appData = AppData.fromJson(jsonMap);

    // Find the application that matches the key, and execute onData() callback
    final appName = appData.app;
    var app = _keyToApp[appName]?? _defaultApp;
    app?.onData(node, appName, appData.type, appData.data);
  }

  void _checkSponsors() {
    // Traverse all sponsors:
    // 1) If status is unknown, try to resolve host name
    // 2) If status is resolved, try to connect
    // for(var v in _villagers) {
    //   final status = v.getStatus();
    //   if(status == VillagerStatus.unknown) {
    //     _tryToResolve(v);
    //   } else if(status == VillagerStatus.resolved) {
    //     _tryToConnect(v);
    //   }
    // }
  }
  void _tryToResolve(VillagerNode node) {
    MyLogger.info('${logPrefix} Try to resolve ${node.host}');
    InternetAddress.lookup(node.host).then((values) {
      if(values.length == 0) return;
      node.setResolved(values[0]);
      _addConnectTasks([node]);
      MyLogger.info('${logPrefix} Host(${node.host}) resolve to IP address(${node.ip?.address})');
    }).onError((error, stackTrace) {
      node.setResolveFailed();
    });
  }
  void _tryToConnect(VillagerNode node) {
    MyLogger.info('${logPrefix} Try to connect to ${node.ip?.address}:${node.port}');
    final peerIp = node.ip!;
    final peerPort = node.port;
    node.setConnecting();
    var peer = _network.connect(peerIp.address, peerPort,
      onReceive: (data) {
        _onRawData(node, data);
      },
      onDisconnect: _onDisconnect,
      onConnectionFail: _onConnectionFail
    );
    if(peer != null) {
      node.setPeer(peer);
    }
  }
  void _tryToReconnect() {
    int now = networkNow();
    var reconnectVillages = <VillagerNode>[];
    for(var node in _villagers) {
      final status = node.getStatus();
      if(status == VillagerStatus.unknown || status == VillagerStatus.lostContact) {
        if(now - node.failedTimestamp >= node.currentReconnectIntervalInSeconds * 1000) {
          reconnectVillages.add(node);
        }
      }
    }
    _addConnectTasks(reconnectVillages);
  }

  String _introduceMyselfMessage() {
    final hello = HelloMessage(_deviceId, userInfo.userName, userInfo.publicKey);
    return jsonEncode(hello);
  }

  void _handleHelloMessage(VillagerNode node, String msg) {
    var hello = HelloMessage.fromJson(jsonDecode(msg));
    node.id = hello.deviceId;
    node.publicKey = hello.publicKey;
    node.name = hello.name;
    onNodeChanged(node);
  }

  List<VillagerNode> getAllNodes() {
    var result = <VillagerNode>[];
    for(var node in _villagers) {
      if(node.getStatus() == VillagerStatus.keepInTouch) {
        result.add(node);
      }
    }
    return result;
  }

  VillagerNode? _findVillageByIpAndPort(InternetAddress ip, int port) {
    for(var node in _villagers) {
      if(node.ip == ip && node.port == port) {
        return node;
      }
    }
    return null;
  }
  
  bool _addIntoVillagersIfNotExists(VillagerNode target) {
    for(var v in _villagers) {
      if(v.ip == target.ip && v.port == target.port) {
        return false;
      }
    }
    _villagers.add(target);
    return true;
  }
  bool _alreadyInVillagers(InternetAddress ip, int port) {
    for(var v in _villagers) {
      if(v.ip == ip && v.port == port) {
        return true;
      }
    }
    return false;
  }
}
