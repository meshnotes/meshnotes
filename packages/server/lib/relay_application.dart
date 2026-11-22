import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/overlay/overlay_controller.dart';
import 'package:libp2p/dal/village_db.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:libp2p/utils.dart';
import 'package:my_log/my_log.dart';
import 'package:server/server_db.dart';
import 'package:libp2p/application/version_chain_api.dart';

class _QueryFlow {
  final String user;
  final String appName;
  final Object? peer;
  final List<String> pending = [];
  List<String> keys = [];
  String? id;
  int attempts = 0;
  final Set<String> received = {};
  int? expected;
  bool failed = false;
  Timer? timer;
  
  _QueryFlow(this.user, this.appName, this.peer);
}

class RelayApplication implements ApplicationController {
  static const logPrefix = '[RelayApplication]';
  static const latestVersionKey = 'latest_version';
  static const latestVersionTimestampKey = 'latest_version_timestamp';
  static const defaultMaxQueryVersionsPerApply = 2;
  static const defaultPublishIntervalSeconds = 300;
  static const defaultPendingTimeoutMs = 600000;
  static const defaultMaxPendingQueries = 5;
  final VillageOverlay _overlay;
  final ServerDbHelper _serverDb;
  final SigningWrapper _signing;
  final String upperAppName;
  final int maxQueryVersionsPerApply;
  final int publishIntervalSeconds;
  final int pendingTimeoutMs;
  final int maxPendingQueries;
  static const queryTimeout = Duration(seconds: 60 * 5);
  static const maxQueryAttempts = 3;
  final Map<VillagerNode, _QueryFlow> _queryFlows = {};
  final Map<String, Set<String>> _incompleteVersionsByUser = {};
  final Map<String, String> _lastForwardedLatestVersionByUser = {};
  Timer? _publishTimer;
  final Map<String, AppMessageType> _mapOfAppMessageType = {};

  RelayApplication({
    required VillageOverlay overlay,
    required VillageDbHelper db,
    required ServerDbHelper serverDb,
    required SigningWrapper signing,
    required this.upperAppName,
    int maxQueryVersionsPerApply = defaultMaxQueryVersionsPerApply,
    int publishIntervalSeconds = defaultPublishIntervalSeconds,
    int pendingTimeoutMs = defaultPendingTimeoutMs,
    int maxPendingQueries = defaultMaxPendingQueries,
  })  : _overlay = overlay,
        _serverDb = serverDb,
        _signing = signing,
        maxQueryVersionsPerApply = maxQueryVersionsPerApply <= 0? defaultMaxQueryVersionsPerApply : maxQueryVersionsPerApply,
        publishIntervalSeconds = publishIntervalSeconds < 0? defaultPublishIntervalSeconds : publishIntervalSeconds,
        pendingTimeoutMs = pendingTimeoutMs < 0? defaultPendingTimeoutMs : pendingTimeoutMs,
        maxPendingQueries = maxPendingQueries <= 0? defaultMaxPendingQueries : maxPendingQueries {
    MyLogger.info('$logPrefix register app=relay_village');
    _overlay.registerApplication('relay_village', this, setDefault: true);
    _overlay.registerApplication(upperAppName, this);
    for(var e in AppMessageType.values) {
      _mapOfAppMessageType[e.value] = e;
    }
  }

  @override
  void onData(VillagerNode node, String appName, String type, String data) {
    MyLogger.debug('$logPrefix: Receive village data of type($type) to application($appName): ${shortenString(data)}');

    var appType = _mapOfAppMessageType[type];
    if(appType == null) {
      MyLogger.warn('$logPrefix onData: receive unrecognized app type: $type, data: ${shortenString(data)}');
      return;
    }

    switch(appType) {
      case AppMessageType.provideAppType:
        _handleProvide(data, node, appName);
        break;
      case AppMessageType.queryAppType:
        _handleQuery(data, node, appName);
        break;
      case AppMessageType.publishAppType:
        _handlePublish(node.publicKey, data, node, appName);
        break;
      case AppMessageType.applyAppType:
        _handleApply(data, appName, node);
        break;
      case AppMessageType.offerAppType:
        // Normally server is the one sending offers, ignore if received
        break;
    }
  }

  void _handleProvide(String data, VillagerNode node, String appName) {
    MyLogger.info('$logPrefix Received provideAppType data. Storing/Handling...');
    try {
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      final transaction = TransactionMessage.isTransaction(decoded) ? TransactionMessage.fromJson(decoded) : null;
      if(transaction != null && (transaction.status == TransactionStatus.request || transaction.userPublicId != node.publicKey ||
          !_verifyTextWithSenderPublicKey(transaction.toSignableString(), transaction.signature, node.publicKey))) {
        MyLogger.warn('$logPrefix Drop incorrect query: transaction=$transaction, publicKey=$node.publicKey');
        return;
      }
      if(transaction?.status == TransactionStatus.completed && transaction?.objectCount == null) {
        MyLogger.warn('$logPrefix Drop completed sync response without object count');
        return;
      }
      final cipherMessages = transaction == null ? CipherMessages.fromJson(decoded) : transaction.parseCipher();
      final userPublicKey = cipherMessages.userPublicId;
      if(userPublicKey != node.publicKey) {
        MyLogger.warn('$logPrefix Drop provide because its user does not match the connected node: message_user=$userPublicKey, ${_nodeLabel(node)}');
        return;
      }
      if(!_verifyTextWithSenderPublicKey(cipherMessages.getSignableFeature(), cipherMessages.signature, userPublicKey)) {
        MyLogger.warn('$logPrefix Drop provide because the batch signature failed: message_user=$userPublicKey, resource_count=${cipherMessages.resources.length}, ${_nodeLabel(node)}');
        return;
      }
    
      final flow = _queryFlows[node];
      final tracked = transaction != null;
      if(tracked && (flow == null || flow.id != transaction.transactionId || flow.user != userPublicKey ||
          flow.appName != appName || !identical(flow.peer, node.getPeer()) || flow.failed)) {
        MyLogger.warn('$logPrefix Incorrect query flow for node ${_nodeLabel(node)}');
        return;
      }
      final savedResources = <String>{};
      for(var resource in cipherMessages.resources) {
        final feature = UnsignedResource(key: resource.key, subKey: resource.subKey, timestamp: resource.timestamp, data: resource.data).getFeature();
        if(!_verifyTextWithSenderPublicKey(feature, resource.signature, userPublicKey)) {
          if(tracked) flow!.failed = true;
          continue;
        }
        if(resource.key == resourceKeyVersionTree) {
          // A matching pending claim becomes the steady head only after its tree arrives.
          // Until then the previously stored tree stays available.
          if(!_serverDb.tryPromotePendingClaim(userPublicKey: userPublicKey, versionTree: resource)) {
            final current = _serverDb.getLatestVersion(userPublicKey, latestVersionKey);
            if(current == null || resource.subKey != current || resource.timestamp != _serverDb.getLatestPublishVersionTimestamp(userPublicKey)) {
              continue;
            }
            _serverDb.saveVersionTree(userPublicKey: userPublicKey, resource: resource);
          }
        } else {
          _serverDb.saveObject(
            userPublicKey: userPublicKey,
            key: resource.key,
            subKey: resource.subKey,
            timestamp: resource.timestamp,
            data: resource.data,
            signature: resource.signature,
          );
        }
        savedResources.add(resource.key);
      }
      if(tracked) {
        final active = flow!;
        final before = active.received.length;
        active.received.addAll(savedResources);
        if(transaction.status == TransactionStatus.failed) {
          active.failed = true;
        }
        if(transaction.status == TransactionStatus.completed) {
          if(active.expected != null && active.expected != transaction.objectCount) {
            active.failed = true;
          }
          active.expected = transaction.objectCount;
        }
        if(active.expected != null && active.received.length > active.expected!) {
          active.failed = true;
        }
        if(!active.failed && active.expected == active.received.length && active.keys.every(active.received.contains)) {
          active.timer?.cancel();
          MyLogger.info('$logPrefix Query batch saved: user=$userPublicKey, transaction=${active.id}, unique_objects=${active.received.length}');
          _incompleteVersionsByUser[userPublicKey]?.removeAll(active.keys);
          active.keys = [];
          active.id = null;
          _forwardStoredLatestPublishIfReady(userPublicKey, sourceNode: node);
          _sendNextMissingVersionQuery(userPublicKey, appName, node);
        } else if(active.received.length > before && !active.failed) {
          _armQueryTimeout(node, active);
        }
      } else {
        _forwardStoredLatestPublishIfReady(userPublicKey, sourceNode: node);
      }
    } catch(e) {
      MyLogger.warn('$logPrefix Failed to parse/save provideAppType data: $e');
    }
  }

  void _handleQuery(String data, VillagerNode node, String appName) {
    MyLogger.info('$logPrefix Received queryAppType data.');
    String? transactionId;
    try {
      final decoded = jsonDecode(data) as Map<String, dynamic>;
      final transaction = TransactionMessage.isTransaction(decoded) ? TransactionMessage.fromJson(decoded) : null;
      if(transaction != null && (transaction.status != TransactionStatus.request || transaction.userPublicId != node.publicKey ||
          !_verifyTextWithSenderPublicKey(transaction.toSignableString(), transaction.signature, node.publicKey))) {
        return;
      }
      final uncipherMessage = transaction == null ? UncipherMessage.fromJson(decoded) : transaction.parseUncipher();
      final userPublicKey = uncipherMessage.userPublicId;
      final requireVersions = RequireVersions.fromJson(jsonDecode(uncipherMessage.data));
      if(userPublicKey != node.publicKey || !_verifyUncipherMessage(uncipherMessage)) {
        return;
      }
      transactionId = transaction?.transactionId;
      final keys = requireVersions.requiredVersions;
      final resources = <CipherMessage>[];
      if(keys.contains(resourceKeyVersionTree)) {
        final tree = _serverDb.getVersionTree(userPublicKey);
        if(tree != null) {
          resources.add(tree);
        }
      }
      final objectKeys = keys.where((key) => key != resourceKeyVersionTree).toSet().toList();
      resources.addAll(_serverDb.getObjects(userPublicKey, objectKeys));
      MyLogger.info('$logPrefix Found ${resources.length} stored objects for user $userPublicKey');
      if(resources.isNotEmpty || transactionId != null) {
        final dataToSend = _buildProvidePayload(resources, transactionId, false);
        _overlay.sendData(appName, this, node, AppMessageType.provideAppType.value, dataToSend);
      }
    } catch(e) {
      MyLogger.warn('$logPrefix Failed to handle queryAppType: $e');
      if(transactionId != null) {
        final dataToSend = _buildProvidePayload([], transactionId, true);
        try {
          _overlay.sendData(appName, this, node, AppMessageType.provideAppType.value, dataToSend);
        } catch(sendError) {
          MyLogger.warn('$logPrefix Failed to report query error: transaction=$transactionId, error=$sendError');
        }
      }
    }
  }

  /// A version_chain is used as-is. A version_tree_resolve is unwrapped once to its signed publish.
  ({String payload, Map<String, dynamic> broadcast, String? resolvedVersion})? _readVersionPublish(String data) {
    final body = jsonDecode(data) as Map<String, dynamic>;
    if(body['type'] == versionChainBroadcastType) {
      // resolved_version belongs to the version_tree_resolve envelope, not the original signed version_chain.
      if(body.containsKey(resolvedVersionKey)) {
        return null;
      }
      return (payload: data, broadcast: body, resolvedVersion: null);
    }
    if(body['type'] != versionTreeResolveType) return null;
    final resolve = VersionTreeResolve.fromJson(body);
    final broadcast = jsonDecode(resolve.publish) as Map<String, dynamic>;
    if(broadcast['type'] != versionChainBroadcastType || broadcast.containsKey(resolvedVersionKey)) {
      return null;
    }
    return (payload: resolve.publish, broadcast: broadcast, resolvedVersion: resolve.resolvedVersion);
  }

  void _handlePublish(String senderPublicKey, String data, VillagerNode node, String appName) {
    MyLogger.info('$logPrefix Received publishAppType data. Storing/Handling...');
    try {
      final decoded = jsonDecode(data);
      final uncipherMessage = UncipherMessage.fromJson(decoded);
      final senderKey = uncipherMessage.userPublicId;
      if(senderKey != senderPublicKey) {
        MyLogger.warn('$logPrefix Publish received from unexpected sender: sender_key=$senderKey, expected_sender_key=$senderPublicKey');
        return;
      }
      if(!_verifyTextWithSenderPublicKey(uncipherMessage.data, uncipherMessage.signature, senderPublicKey)) {
        MyLogger.warn('$logPrefix Failed to verify publishAppType signature for sender $senderPublicKey');
        return;
      }
      final parsed = _readVersionPublish(uncipherMessage.data);
      if(parsed == null) return;
      final uncipherData = parsed.payload;
      final resolvedVersion = parsed.resolvedVersion;
      final brdMsg = BroadcastMessages.fromJson(parsed.broadcast);
      final ownerPublicKey = brdMsg.userPublicId;
      if(ownerPublicKey != senderPublicKey) return;
      if(!_verifyTextWithSenderPublicKey(brdMsg.toSignableString(), brdMsg.signature, ownerPublicKey)) {
        MyLogger.warn('$logPrefix Failed to verify publishAppType signature for owner $ownerPublicKey');
        return;
      }
      final messages = brdMsg.messages;
      if(messages.isNotEmpty) {  final latestVersion = messages[latestVersionKey];
        if(latestVersion != null && latestVersion.isNotEmpty) {
          final latestVersionTimestamp = int.tryParse(messages[latestVersionTimestampKey]?.toString() ?? '');
          final oldLatestVersion = _serverDb.getLatestVersion(ownerPublicKey, latestVersionKey);
          final oldLatestPublishVersionTimestamp = _serverDb.getLatestPublishVersionTimestamp(ownerPublicKey);
          // The publish timestamp is only a hint that says which version_tree timestamp the peer has.
          // Do not store it as the relay cache timestamp; compare it with the stored version_tree resource timestamp instead.
          final versionTreeTimestamp = _serverDb.getVersionTreeTimestamp(ownerPublicKey);
          final hasLatestVersionObject = _hasCompleteVersion(ownerPublicKey, latestVersion);
          final samePublishVersion = oldLatestVersion == latestVersion && (latestVersionTimestamp == null || oldLatestPublishVersionTimestamp == latestVersionTimestamp);
          MyLogger.info('$logPrefix Publish latest_version received: user=$ownerPublicKey, node=${_nodeLabel(node)}, latest_version=$latestVersion, publish_timestamp=$latestVersionTimestamp, old_latest_version=$oldLatestVersion, old_publish_timestamp=$oldLatestPublishVersionTimestamp, same_publish_version=$samePublishVersion, stored_version_tree_timestamp=$versionTreeTimestamp, has_latest_version_object=$hasLatestVersionObject');
          final admission = _serverDb.tryAdmitPublish(ownerPublicKey, latestVersion, latestVersionTimestamp, uncipherData, resolvedVersion, timeoutMs: pendingTimeoutMs, maxQueries: maxPendingQueries);
          if(admission.conflictVersion != null) {
            if(admission.conflictVersion!.isNotEmpty) {
              final body = jsonEncode(VersionTreeConflict(conflictVersion: admission.conflictVersion!, owner: ownerPublicKey));
              final reply = UncipherMessage(
                userPublicId: _signing.getCompressedPublicKey(),
                data: body,
                signature: _signing.sign(HashUtil.hashText(body)),
              );
              _overlay.sendData(appName, this, node, AppMessageType.publishAppType.value, jsonEncode(reply));
            }
            return;
          }
          if(admission.busy) {
            MyLogger.info('$logPrefix Ignore publish while a pending version claim is in progress: user=$ownerPublicKey, claimed_version=$latestVersion');
            return;
          }
          if(admission.pending) {
            _sendVersionTreeQuery(appName, node, ownerPublicKey, latestVersionTimestamp, versionTreeTimestamp);
            _serverDb.recordPendingQuery(ownerPublicKey);
            if(!hasLatestVersionObject) {
              _sendStorageOffer(appName, node, ownerPublicKey, latestVersion, latestVersionTimestamp);
            }
            return;
          }
          if(oldLatestVersion != latestVersion || _shouldRequestVersionTree(latestVersionTimestamp, versionTreeTimestamp)) {
            _sendVersionTreeQuery(appName, node, ownerPublicKey, latestVersionTimestamp, versionTreeTimestamp);
          }
          if(hasLatestVersionObject && samePublishVersion && latestVersionTimestamp != null && versionTreeTimestamp == latestVersionTimestamp) {
            MyLogger.info('$logPrefix Latest version unchanged for user $ownerPublicKey and version tree timestamp matches publish timestamp. Skip sending offer.');
            if(_serverDb.hasObject(ownerPublicKey, latestVersion)) {
              _forwardPublishToSameUserNodes(ownerPublicKey, uncipherData, sourceNode: node);
              _lastForwardedLatestVersionByUser[ownerPublicKey] = latestVersion;
            }
            return;
          }
          if(!hasLatestVersionObject) {
            _sendStorageOffer(appName, node, ownerPublicKey, latestVersion, latestVersionTimestamp);
          } else {
            _forwardPublishToSameUserNodes(ownerPublicKey, uncipherData, sourceNode: node);
            _lastForwardedLatestVersionByUser[ownerPublicKey] = latestVersion;
          }
        }
      }
      // TODO: Before re-enabling publish relay, record which latest_version values have already been forwarded to avoid relay storms.
    } catch(e) {
      MyLogger.warn('$logPrefix Failed to handle publishAppType: $e');
    }
  }

  void _handleApply(String data, String appName, VillagerNode node) {
    MyLogger.info('$logPrefix Received applyAppType data. Processing apply...');
    try {
      final decoded = jsonDecode(data);
      final uncipherMessage = UncipherMessage.fromJson(decoded);
      final userPublicKey = uncipherMessage.userPublicId;
      if(userPublicKey != node.publicKey || !_verifyUncipherMessage(uncipherMessage)) {
        MyLogger.warn('$logPrefix Failed to verify applyAppType signature for user $userPublicKey');
        return;
      }
      final applyObj = Apply.fromJson(jsonDecode(uncipherMessage.data));
      if(applyObj.type != applyTypeVersion) {
        MyLogger.info('$logPrefix Ignore unsupported apply type: ${applyObj.type}');
        return;
      }
      final versionHashes = _stringListFromApplyData(applyObj.data[applyTypeVersionsKey]);
    
      final missingVersions = versionHashes.toSet().where((version) => !_hasCompleteVersion(userPublicKey, version)).toList();
      final flow = _flowFor(userPublicKey, appName, node);
      for(final version in missingVersions) {
        if(!flow.keys.contains(version) && !flow.pending.contains(version)) {
          flow.pending.add(version);
          if(version != resourceKeyVersionTree) {
            _incompleteVersionsByUser.putIfAbsent(userPublicKey, () => <String>{}).add(version);
          }
        }
      }
      MyLogger.info('$logPrefix Total versions in apply: ${versionHashes.length}, missing: ${missingVersions.length}');
      _sendNextMissingVersionQuery(userPublicKey, appName, node);
    } catch(e) {
      MyLogger.warn('$logPrefix Failed to handle applyAppType: $e');
    }
  }

  String _buildQueryPayload(List<String> keys, String transactionId) {
    final requireVersions = RequireVersions(requiredVersions: keys);
    final data = jsonEncode(requireVersions);
    final uncipherMessage = UncipherMessage(
      userPublicId: _signing.getCompressedPublicKey(),
      data: data,
      signature: _signing.sign(HashUtil.hashText(data)),
    );
    final transaction = TransactionMessage(
      transactionId: transactionId,
      status: TransactionStatus.request,
      contentType: TransactionContentType.uncipher,
      data: jsonEncode(uncipherMessage),
      userPublicId: _signing.getCompressedPublicKey(),
      signature: ''
    );
    transaction.signature = _signing.sign(HashUtil.hashText(transaction.toSignableString()));
    return jsonEncode(transaction);
  }

  String _buildProvidePayload(List<CipherMessage> resources, String? transactionId, bool failed) {
    final cipherMessages = CipherMessages(
      userPublicId: _signing.getCompressedPublicKey(),
      resources: resources,
      signature: '',
    );
    cipherMessages.signature = _signing.sign(HashUtil.hashText(cipherMessages.getSignableFeature()));
    if(transactionId == null) return jsonEncode(cipherMessages);
    final transaction = TransactionMessage(
      transactionId: transactionId,
      status: failed ? TransactionStatus.failed : TransactionStatus.completed,
      contentType: TransactionContentType.cipher,
      data: jsonEncode(cipherMessages),
      objectCount: resources.length,
      userPublicId: _signing.getCompressedPublicKey(),
      signature: ''
    );
    transaction.signature = _signing.sign(HashUtil.hashText(transaction.toSignableString()));
    return jsonEncode(transaction);
  }

  bool _shouldRequestVersionTree(int? publishTimestamp, int? storedVersionTreeTimestamp) {
    if(storedVersionTreeTimestamp == null) {
      return true;
    }
    if(publishTimestamp == null) {
      return false;
    }
    return storedVersionTreeTimestamp != publishTimestamp;
  }

  void _sendStorageOffer(String appName, VillagerNode node, String ownerPublicKey, String latestVersion, int? latestVersionTimestamp) {
    final offer = Offer(
      type: offerTypeStorage,
      target: ownerPublicKey,
      data: {
        'limit': 100,
        'extra': '',
      },
    );
    final offerData = jsonEncode(offer);
    final uncipherOffer = UncipherMessage(
      userPublicId: _signing.getCompressedPublicKey(),
      data: offerData,
      signature: _signing.sign(HashUtil.hashText(offerData)),
    );
    final offerPayload = jsonEncode(uncipherOffer);
    final timestampText = latestVersionTimestamp == null? '' : '(timestamp=$latestVersionTimestamp)';
    MyLogger.info('$logPrefix Missing version $latestVersion$timestampText for user $ownerPublicKey.'
        ' Sending offer(type=$offerTypeStorage) to ${node.nodeId}.');
    _overlay.sendData(appName, this, node, AppMessageType.offerAppType.value, offerPayload);
  }

  void _sendVersionTreeQuery(String appName, VillagerNode node, String userPublicKey, int? publishTimestamp, int? storedVersionTreeTimestamp) {
    MyLogger.info('$logPrefix Query version_tree from publish source: user=$userPublicKey, node=${_nodeLabel(node)}, publish_timestamp=$publishTimestamp, stored_version_tree_timestamp=$storedVersionTreeTimestamp');
    final flow = _flowFor(userPublicKey, appName, node);
    if(!flow.keys.contains(resourceKeyVersionTree) && !flow.pending.contains(resourceKeyVersionTree)) {
      flow.pending.insert(0, resourceKeyVersionTree);
    }
    _sendNextMissingVersionQuery(userPublicKey, appName, node);
  }

  _QueryFlow _flowFor(String user, String appName, VillagerNode node) {
    final previous = _queryFlows[node];
    if(previous != null && previous.user == user && previous.appName == appName && identical(previous.peer, node.getPeer())) {
      return previous;
    }
    previous?.timer?.cancel();
    return _queryFlows[node] = _QueryFlow(user, appName, node.getPeer());
  }

  void _sendNextMissingVersionQuery(String userPublicKey, String appName, VillagerNode node) {
    final flow = _queryFlows[node];
    if(flow == null || flow.id != null) return;
    flow.pending.removeWhere((key) => key != resourceKeyVersionTree && _serverDb.hasObject(userPublicKey, key) &&
      !(_incompleteVersionsByUser[userPublicKey]?.contains(key) ?? false));
    if(flow.pending.isEmpty) {
      _queryFlows.remove(node);
      return;
    }
    // Tree requests share the same connection slot but are answered independently of version bundles.
    final batchSize = flow.pending.first == resourceKeyVersionTree ? 1 : min(flow.pending.takeWhile((key) => key != resourceKeyVersionTree).length, maxQueryVersionsPerApply);
    flow.keys = flow.pending.sublist(0, batchSize);
    flow.pending.removeRange(0, batchSize);
    flow.attempts = 0;
    _sendQueryAttempt(node, flow);
  }

  void _sendQueryAttempt(VillagerNode node, _QueryFlow flow) {
    flow.id = TransactionUtil.generateTransactionId();
    flow.attempts++;
    flow.received.clear();
    flow.expected = null;
    flow.failed = false;
    MyLogger.info('$logPrefix Query missing versions for user ${flow.user}: query_now=${flow.keys.length}, pending_for_connection=${flow.pending.length}, attempt=${flow.attempts}, transaction=${flow.id}');
    // TEMPORARY LOG: Full hashes for sync diagnosis; remove after investigation.
    MyLogger.info('$logPrefix Query version hashes: user=${flow.user}, target=${_nodeLabel(node)}, transaction=${flow.id}, versions=${jsonEncode(flow.keys)}');
    _armQueryTimeout(node, flow);
    try {
      _overlay.sendData(flow.appName, this, node, AppMessageType.queryAppType.value, _buildQueryPayload(flow.keys, flow.id!));
    } catch(e) {
      flow.failed = true;
      MyLogger.warn('$logPrefix Query send failed: transaction=${flow.id}, error=$e');
    }
  }

  void _armQueryTimeout(VillagerNode node, _QueryFlow flow) {
    flow.timer?.cancel();
    flow.timer = Timer(queryTimeout, () {
      if(!identical(_queryFlows[node], flow)) return;
      if(node.getStatus() != VillagerStatus.keepInTouch || !identical(flow.peer, node.getPeer()) || node.publicKey != flow.user || flow.attempts >= maxQueryAttempts) {
        MyLogger.warn('$logPrefix Query failed: user=${flow.user}, transaction=${flow.id}, attempts=${flow.attempts}; waiting for a fresh publish/apply');
        _queryFlows.remove(node);
        return;
      }
      MyLogger.warn('$logPrefix Query timeout/retry: user=${flow.user}, transaction=${flow.id}, saved=${flow.received.length}, expected=${flow.expected}, failed=${flow.failed}');
      _sendQueryAttempt(node, flow);
    });
  }

  bool _hasCompleteVersion(String user, String version) {
    return _serverDb.hasObject(user, version) && !(_incompleteVersionsByUser[user]?.contains(version) ?? false);
  }

  void _forwardStoredLatestPublishIfReady(String userPublicKey, {VillagerNode? sourceNode}) {
    final latestVersion = _serverDb.getLatestVersion(userPublicKey, latestVersionKey);
    if(latestVersion == null) {
      MyLogger.info('$logPrefix Skip forwarding stored publish for user $userPublicKey: no latest_version cached.');
      return;
    }
    if(!_hasCompleteVersion(userPublicKey, latestVersion)) {
      MyLogger.info('$logPrefix Skip forwarding stored publish for user $userPublicKey: latest_version=$latestVersion is not cached yet.');
      return;
    }
    if(_lastForwardedLatestVersionByUser[userPublicKey] == latestVersion) {
      MyLogger.info('$logPrefix Skip forwarding stored publish for user $userPublicKey: latest_version=$latestVersion was already forwarded.');
      return;
    }
    final records = _serverDb.getLatestPublishPayloads().where((record) => record.userPublicKey == userPublicKey && record.latestVersion == latestVersion);
    if(records.isEmpty) {
      MyLogger.info('$logPrefix Skip forwarding stored publish for user $userPublicKey: no stored publish payload for latest_version=$latestVersion.');
      return;
    }
    MyLogger.info('$logPrefix Forward stored publish after cache ready: user=$userPublicKey, latest_version=$latestVersion, source=${_nodeLabel(sourceNode)}');
    _forwardPublishToSameUserNodes(userPublicKey, records.first.payload, sourceNode: sourceNode);
    _lastForwardedLatestVersionByUser[userPublicKey] = latestVersion;
  }

  void _expireAndRetryPendingClaims() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _serverDb.expirePendingClaims(now, pendingTimeoutMs, maxPendingQueries);
    for(final claim in _serverDb.getPendingClaims()) {
      VillagerNode? target;
      for(final node in _overlay.getAllNodes()) {
        if(node.publicKey == claim.userPublicKey && node.getStatus() == VillagerStatus.keepInTouch) {
          target = node;
          break;
        }
      }
      if(target == null) continue;
      MyLogger.info('$logPrefix Retry pending version claim: user=${claim.userPublicKey}, claimed_version=${claim.claimedVersion}, query_attempts=${claim.queryAttempts}');
      _sendVersionTreeQuery(upperAppName, target, claim.userPublicKey, claim.claimedTimestamp, _serverDb.getVersionTreeTimestamp(claim.userPublicKey));
      _serverDb.recordPendingQuery(claim.userPublicKey);
    }
  }

  void _broadcastLatestPublishesToSameUserNodes() {
    final records = _serverDb.getLatestPublishPayloads();
    MyLogger.info('$logPrefix Periodic publish forwarding tick: cached_publish_users=${records.length}, interval=${publishIntervalSeconds}s');
    for(final record in records) {
      if(!_hasCompleteVersion(record.userPublicKey, record.latestVersion)) {
        MyLogger.info('$logPrefix Periodic publish skip user ${record.userPublicKey}: latest_version=${record.latestVersion} is not cached yet.');
        continue;
      }
      MyLogger.info('$logPrefix Periodic publish forward user=${record.userPublicKey}, latest_version=${record.latestVersion}');
      _forwardPublishToSameUserNodes(record.userPublicKey, record.payload);
    }
  }

  void _forwardPublishToSameUserNodes(String userPublicKey, String publishPayload, {VillagerNode? sourceNode}) {
    final publishAppType = AppMessageType.publishAppType.value;
    final nodes = _overlay.getAllNodes();
    var sameUserTotal = 0;
    var sameUserConnected = 0;
    var sent = 0;
    // Package the payload with the signature of current server node
    String signature = _signing.sign(HashUtil.hashText(publishPayload));
    UncipherMessage uncipherMessage = UncipherMessage(userPublicId: _signing.getCompressedPublicKey(), data: publishPayload, signature: signature);
    String realPayload = jsonEncode(uncipherMessage);
    // Send the real payload to the nodes
    MyLogger.info('$logPrefix Searching owner-user-key nodes for publish: owner_user_key=$userPublicKey, total_nodes=${nodes.length}, source=${_nodeLabel(sourceNode)}');
    for(final node in nodes) {
      final status = node.getStatus();
      final label = _nodeLabel(node);
      if(identical(node, sourceNode)) {
        MyLogger.debug('$logPrefix Publish candidate skip source node: $label');
        continue;
      }
      if(node.publicKey != userPublicKey) {
        MyLogger.debug('$logPrefix Publish candidate skip different owner user key: $label, owner_user_key=$userPublicKey');
        continue;
      }
      sameUserTotal++;
      MyLogger.info('$logPrefix Found node with matching owner user key: owner_user_key=$userPublicKey, node=$label');
      if(status != VillagerStatus.keepInTouch) {
        MyLogger.info('$logPrefix Publish candidate skip not connected: $label');
        continue;
      }
      sameUserConnected++;
      MyLogger.info('$logPrefix Sending publish to owner-user-key node: owner_user_key=$userPublicKey, node=$label, app=$upperAppName, type=$publishAppType, payload_len=${publishPayload.length}');
      _overlay.sendData(upperAppName, this, node, publishAppType, realPayload);
      sent++;
      MyLogger.info('$logPrefix Publish sent to owner-user-key node: owner_user_key=$userPublicKey, node=$label, app=$upperAppName, type=$publishAppType, sent_count=$sent');
    }
    MyLogger.info('$logPrefix Forward publish summary: owner_user_key=$userPublicKey, total_nodes=${nodes.length}, matching_owner_user_key=$sameUserTotal, matching_owner_user_key_connected=$sameUserConnected, sent=$sent');
  }

  String _nodeLabel(VillagerNode? node) {
    if(node == null) {
      return '-';
    }
    return 'node_id=${node.nodeId}, id=${node.id}, public_key=${node.publicKey}, host=${node.host}, port=${node.port}, status=${node.getStatus().name}';
  }

  List<String> _stringListFromApplyData(dynamic data) {
    if(data is! List) {
      return [];
    }
    final result = <String>[];
    for(final item in data) {
      if(item is String) {
        result.add(item);
      }
    }
    return result;
  }

  bool _verifyUncipherMessage(UncipherMessage message) {
    try {
      final verifier = VerifyingWrapper.loadKey(message.userPublicId);
      return verifier.ver(HashUtil.hashText(message.data), message.signature);
    } catch(e) {
      MyLogger.warn('$logPrefix Failed to verify uncipher message for user ${message.userPublicId}: $e');
      return false;
    }
  }

  bool _verifyTextWithSenderPublicKey(String message, String signature, String senderPublicKey) {
    try {
      final verifier = VerifyingWrapper.loadKey(senderPublicKey);
      return verifier.ver(HashUtil.hashText(message), signature);
    } catch(e) {
      MyLogger.warn('$logPrefix Failed to verify uncipher message for user $senderPublicKey: $e');
      return false;
    }
  }

  Future<void> start() async {
    await _overlay.start();
    if(publishIntervalSeconds > 0) {
      _publishTimer?.cancel();
      _publishTimer = Timer.periodic(Duration(seconds: publishIntervalSeconds), (_) {
        _expireAndRetryPendingClaims();
        _broadcastLatestPublishesToSameUserNodes();
      });
      MyLogger.info('$logPrefix Started periodic publish forwarding: interval=${publishIntervalSeconds}s');
    }
    MyLogger.info('$logPrefix Started relay application overlay.');
  }
}
