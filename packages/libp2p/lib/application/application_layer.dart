import 'dart:async';
import 'dart:convert';
import 'package:keygen/keygen.dart';
import 'package:libp2p/dal/village_db.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/overlay_controller.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:libp2p/utils.dart';
import 'package:my_log/my_log.dart';
import 'application_api.dart';

// Only the protocol layer owns the original connection and route expiry.
class _QueryReplyRoute {
  final String nodeId;
  final int? connectionId;
  final bool transactional;
  Timer? timeout;
  _QueryReplyRoute(this.nodeId, this.connectionId, this.transactional);
}

enum VillageMode {
  loneWolf,
}

class Village implements ApplicationController {
  static const logPrefix = '[Village]';
  static const _appName = 'village';
  VillageOverlay _overlay;
  VillageMode _mode;
  String upperAppName;
  VillageMessageHandler messageHandler;
  VillageDbHelper _db;
  Map<String, AppMessageType> _mapOfAppMessageType = {};
  int _lastPrintStatisticsTimestamp = 0;
  static const _printStatisticsInterval = 10000; // Print statistics every 10 seconds
  _TimeCostStatistics _timeCostStatistics = _TimeCostStatistics();
  final Map<String, _QueryReplyRoute> _queryReplyRoutes = {};
  static const _queryReplyTimeout = Duration(minutes: 5);

  // Villager properties
  // String _userId; // It seems this is not necessary

  Village({
    // required String userId,
    required List<String> sponsors,
    required this.messageHandler,
    VillageMode mode = VillageMode.loneWolf,
    required VillageOverlay overlay,
    required VillageDbHelper db,
    required this.upperAppName,
  }): _mode = mode, /*_userId = userId, */_overlay = overlay, _db = db {
    MyLogger.info('${logPrefix} register app=$_appName');
    _overlay.registerApplication(_appName, this, setDefault: true);
    _overlay.registerApplication(upperAppName, this);
    AppMessageType.values.forEach((e) { _mapOfAppMessageType[e.value] = e; });
  }

  Future<void> start() async {
    await _overlay.start();
    Timer.periodic(Duration(milliseconds: 5000), _timerHandler);
  }

  /// Handle the data received from lower layer
  @override
  void onData(VillagerNode node, String appName, String type, String data) {
    TimeCostStatistics stats = TimeCostStatistics(
      startTime: networkNow(),
    );
    MyLogger.debug('${logPrefix}: Receive village data of type($type) to application($appName): ${data.substring(0, 100)}');
    var appType = _mapOfAppMessageType[type];
    if(appType == null) {
      MyLogger.warn('onData: receive unrecognized app type: $type, data=$data');
      return;
    }
    String senderPublicKey = node.publicKey;
    switch(appType) {
      case AppMessageType.provideAppType:
        if(upperAppName == appName) {
          messageHandler.handleProvide?.call(senderPublicKey, data, stats);
        } else {
          _onDefaultProvide(data);
        }
        break;
      case AppMessageType.queryAppType:
        if(upperAppName == appName) {
          _onQuery(node, data, stats);
        } else {
          _onDefaultQuery(data);
        }
        break;
      case AppMessageType.publishAppType:
        if(upperAppName == appName) {
          messageHandler.handlePublish?.call(senderPublicKey, data, stats);
        } else {
          _onDefaultPublish(data);
        }
        break;
      case AppMessageType.offerAppType:
        if(upperAppName == appName) {
          messageHandler.handleOffer?.call(senderPublicKey, data, stats);
        } else {
          _onDefaultOffer(data);
        }
        break;
      case AppMessageType.applyAppType:
        if(upperAppName == appName) {
          messageHandler.handleApply?.call(senderPublicKey, data, stats);
        } else {
          _onDefaultApply(data);
        }
        break;
    }
  }

  void newNodeDiscovered(String host, int port, String deviceId) { // Called if using bonjour and discover new nodes
    _overlay.newNodeDiscovered(host, port, deviceId);
  }

  void sendPublish(String msgJson, TimeCostStatistics stats, String? targetPublicKey) {
    MyLogger.info('sendPublish: Preparing to send publish: ${msgJson.substring(0, 100)}');

    if(targetPublicKey == null) {
      _sendToAllNodesOfUser(AppMessageType.publishAppType, msgJson, stats);
    } else {
      for(final node in _overlay.getAllNodes()) {
        if(node.publicKey == targetPublicKey && node.getStatus() == VillagerStatus.keepInTouch) {
          _overlay.sendData(upperAppName, this, node, AppMessageType.publishAppType.value, msgJson);
        }
      }
    }
  }
  void sendVersionTree(String resourceJson, TimeCostStatistics stats, String? transactionId, bool isComplete) {
    MyLogger.info('sendVersionTree: Preparing to send version tree: ${resourceJson.substring(0, 100)}');
    //TODO Optimize the code below to only send message to selected nodes
    if(transactionId == null) {
      _sendToAllNodesOfUser(AppMessageType.provideAppType, resourceJson, stats);
    } else {
      _sendQueryResponse(resourceJson, stats, transactionId, isComplete);
    }
  }
  void sendRequireVersions(String requiredVersions, TimeCostStatistics stats) {
    MyLogger.info('sendRequireVersions: Preparing to send require_versions: ${requiredVersions.substring(0, 100)}');
    //TODO Optimize the code below to only send message to selected nodes
    _sendToAllNodesOfUser(AppMessageType.queryAppType, requiredVersions, stats);
  }
  void sendVersions(String sendVersions, TimeCostStatistics stats, String? transactionId, bool isComplete) {
    MyLogger.info('sendVersions: Preparing to send versions: ${sendVersions.substring(0, 100)}');
    //TODO Optimize the code below to only send message to selected nodes
    if(transactionId == null) {
      _sendToAllNodesOfUser(AppMessageType.provideAppType, sendVersions, stats);
    } else {
      _sendQueryResponse(sendVersions, stats, transactionId, isComplete);
    }
  }

  void _onQuery(VillagerNode node, String data, TimeCostStatistics stats) {
    if(messageHandler.handleQueryFromNode == null) return;
    late final TransactionMessage? transaction;
    try {
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      transaction = TransactionMessage.isTransaction(decoded) ? TransactionMessage.fromJson(decoded) : null;
      if(transaction != null && !isTransactionQueryCorrect(transaction, node.publicKey)) {
        MyLogger.warn('Skip incorrect query: transaction=$transaction, publicKey=$node.publicKey');
        return;
      }
    } catch(error) {
      MyLogger.warn('Skip malformed query: $error');
      return;
    }
    final transactionId = _rememberQueryRoute(node, transaction?.transactionId, transaction != null);
    if(transactionId != null) {
      messageHandler.handleQueryFromNode!(node.publicKey, transaction?.data ?? data, stats, transactionId);
    }
  }

  bool isTransactionQueryCorrect(TransactionMessage transaction, String publicKey) {
    if(transaction.status != TransactionStatus.request) return false;
    if(transaction.contentType != TransactionContentType.uncipher) return false;
    if(transaction.userPublicId != publicKey) return false;
    if(!VerifyingWrapper.loadKey(publicKey).ver(HashUtil.hashText(transaction.toSignableString()), transaction.signature)) return false;
    return true;
  }

  String? _rememberQueryRoute(VillagerNode node, String? transactionId, bool transactional) {
    // Ordinary queries need only a local ID for targeting their asynchronous reply.
    transactionId ??= 'local-${networkNow()}-${randomId()}';
    if(_queryReplyRoutes.containsKey(transactionId)) {
      MyLogger.warn('Skip duplicate query transaction: $transactionId');
      return null;
    }
    final route = _QueryReplyRoute(node.nodeId, node.getPeer()?.getSourceId(), transactional);
    _queryReplyRoutes[transactionId] = route;
    _renewQueryRoute(transactionId, route);
    return transactionId;
  }

  void _renewQueryRoute(String transactionId, _QueryReplyRoute route) {
    route.timeout?.cancel();
    route.timeout = Timer(_queryReplyTimeout, () {
      _queryReplyRoutes.remove(transactionId);
      MyLogger.info('Expired query response route: transaction=$transactionId');
    });
  }

  void _removeQueryRoute(String transactionId) {
    _queryReplyRoutes.remove(transactionId)?.timeout?.cancel();
  }

  // The producer selects the wire format before serializing the reply.
  bool isTransactionalQuery(String transactionId) => _queryReplyRoutes[transactionId]?.transactional == true;

  void _sendQueryResponse(String data, TimeCostStatistics stats, String transactionId, bool isComplete) {
    final route = _queryReplyRoutes[transactionId];
    if(route == null) {
      MyLogger.info('Skip query response: no active route, transaction=$transactionId');
      return;
    }
    for(final node in _overlay.getAllNodes()) {
      if(node.nodeId == route.nodeId && node.getPeer()?.getSourceId() == route.connectionId && node.getStatus() == VillagerStatus.keepInTouch) {
        _overlay.sendData(upperAppName, this, node, AppMessageType.provideAppType.value, data);
        if(isComplete) {
          _removeQueryRoute(transactionId);
        } else {
          _renewQueryRoute(transactionId, route);
        }
        stats.finishTime = networkNow();
        _updateTimeCostStatistics(stats);
        return;
      }
    }
    _removeQueryRoute(transactionId);
    // A reply belongs to the original connection; disconnects must not reroute it or fail the caller.
    MyLogger.info('Skip query response: requesting connection is no longer available, node=${route.nodeId}, connection=${route.connectionId}');
  }

  void sendOffer(String offerJson, TimeCostStatistics stats) {
    MyLogger.info('sendOffer: Preparing to send offer: ${offerJson.substring(0, offerJson.length > 100? 100 : offerJson.length)}');
    _sendToAllNodesOfUser(AppMessageType.offerAppType, offerJson, stats);
  }
  void sendApply(String applyJson, TimeCostStatistics stats) {
    MyLogger.info('sendApply: Preparing to send apply: ${applyJson.substring(0, applyJson.length > 100? 100 : applyJson.length)}');
    _sendToAllNodesOfUser(AppMessageType.applyAppType, applyJson, stats);
  }
  void _sendToAllNodesOfUser(AppMessageType type, String data, TimeCostStatistics stats) {
    _overlay.sendToAllNodesOfUser(upperAppName, this, type.value, data);
    stats.finishTime = networkNow();
    _updateTimeCostStatistics(stats);
  }

  void _timerHandler(Timer _t) {
    if(_mode == VillageMode.loneWolf) {
      // In lone wolf mode, only sync data to warehouses with the same user_id
      _contactVillagers();
      _syncData();
    }
  }

  void _contactVillagers() {
    //TODO Try hard to keep at least 1 villager is contacted
  }
  void _syncData() {
    var data = _findUpdatedData();
    if(data != null) {
      var nodes = _findWarehousesByUserId();
      _syncDataToWarehouse(nodes, data);
    }
  }
  List<int>? _findUpdatedData() {
    // TODO Find updated data
    return null;
  }
  List<String> _findWarehousesByUserId() {
    // TODO Find node ids by user id
    return [];
  }
  void _syncDataToWarehouse(List<String> nodeIds, List<int> data) {
    // TODO Sync data to warehouses indicated by nodeIds
  }

  /// Not implemented yet
  void _onDefaultProvide(String data) {
  }
  /// Not implemented yet
  void _onDefaultQuery(String data) {
  }
  ///Not implemented yet
  void _onDefaultPublish(String data) {
  }
  ///Not implemented yet
  void _onDefaultOffer(String data) {
  }
  ///Not implemented yet
  void _onDefaultApply(String data) {
  }

  void _updateTimeCostStatistics(TimeCostStatistics stats) {
    final applicationCost = stats.transportTime - stats.startTime;
    final isolateCost = stats.receiveTime - stats.transportTime;
    final protocolCost = stats.finishTime - stats.receiveTime;
    _timeCostStatistics.applicationCostMilliseconds += applicationCost;
    _timeCostStatistics.isolateCostMilliseconds += isolateCost;
    _timeCostStatistics.protocolCostMilliseconds += protocolCost;
    final now = networkNow();
    if(now - _lastPrintStatisticsTimestamp >= _printStatisticsInterval) {
      MyLogger.info('[Village Statistics] Time cost statistics: applicationCost=${_timeCostStatistics.applicationCostMilliseconds}ms, isolateCost=${_timeCostStatistics.isolateCostMilliseconds}ms, protocolCost=${_timeCostStatistics.protocolCostMilliseconds}ms');
      _lastPrintStatisticsTimestamp = now;
    }
  }
}

class _TimeCostStatistics {
  int applicationCostMilliseconds = 0;
  int isolateCostMilliseconds = 0;
  int protocolCostMilliseconds = 0;
}