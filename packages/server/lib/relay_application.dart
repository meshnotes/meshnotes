import 'dart:async';
import 'dart:convert';
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

class RelayApplication implements ApplicationController {
  static const logPrefix = '[RelayApplication]';
  static const latestVersionKey = 'latest_version';
  static const latestVersionTimestampKey = 'latest_version_timestamp';
  static const defaultMaxQueryVersionsPerApply = 2;
  static const defaultPublishIntervalSeconds = 300;
  final VillageOverlay _overlay;
  final ServerDbHelper _serverDb;
  final SigningWrapper _signing;
  final String upperAppName;
  final int maxQueryVersionsPerApply;
  final int publishIntervalSeconds;
  final Map<String, List<String>> _pendingMissingVersionsByUser = {};
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
  })  : _overlay = overlay,
        _serverDb = serverDb,
        _signing = signing,
        maxQueryVersionsPerApply = maxQueryVersionsPerApply <= 0? defaultMaxQueryVersionsPerApply : maxQueryVersionsPerApply,
        publishIntervalSeconds = publishIntervalSeconds < 0? defaultPublishIntervalSeconds : publishIntervalSeconds {
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
      final decoded = jsonDecode(data);
      final cipherMessages = CipherMessages.fromJson(decoded);
      final userPublicKey = cipherMessages.userPublicId;
    
      for(var resource in cipherMessages.resources) {
        if(resource.key == resourceKeyVersionTree) {
          _serverDb.saveVersionTree(userPublicKey: userPublicKey, resource: resource);
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
      }
      _forwardStoredLatestPublishIfReady(userPublicKey, sourceNode: node);
      _sendNextMissingVersionQuery(userPublicKey, appName, node);
    } catch(e) {
      MyLogger.warn('$logPrefix Failed to parse provideAppType data: $e');
    }
  }

  void _handleQuery(String data, VillagerNode node, String appName) {
    MyLogger.info('$logPrefix Received queryAppType data.');
    try {
      final decoded = jsonDecode(data);
      final uncipherMessage = UncipherMessage.fromJson(decoded);
      final userPublicKey = uncipherMessage.userPublicId;
      final requireVersions = RequireVersions.fromJson(jsonDecode(uncipherMessage.data));
      final keys = requireVersions.requiredVersions;
      final requestsVersionTree = keys.contains(resourceKeyVersionTree);
      if(requestsVersionTree) {
        final versionTreeObject = _serverDb.getVersionTree(userPublicKey);
        MyLogger.info('$logPrefix Received version_tree special query: user=$userPublicKey, requester=${_nodeLabel(node)}, has_stored_version_tree=${versionTreeObject != null}');
        if(versionTreeObject == null) {
          MyLogger.info('$logPrefix Cannot answer version_tree query yet: user=$userPublicKey, no stored version_tree. It will be requested from the publish source when the next publish arrives.');
        } else {
          _overlay.sendData(appName, this, node, AppMessageType.provideAppType.value, _buildProvidePayload([versionTreeObject]));
        }
      }
    
      final objectKeys = keys.where((key) => key != resourceKeyVersionTree).toList();
      if(objectKeys.isEmpty) {
        MyLogger.info('$logPrefix Query only contains version_tree special request; handled by version_tree cache.');
        return;
      }
    
      final objects = _serverDb.getObjects(userPublicKey, objectKeys);
      MyLogger.info('$logPrefix Found ${objects.length} stored objects for user $userPublicKey');
      if(objects.isEmpty) {
        MyLogger.info('$logPrefix No objects found for query: user=$userPublicKey, required_versions_count=${objectKeys.length}, required_versions=$objectKeys');
      } else {
        _overlay.sendData(appName, this, node, AppMessageType.provideAppType.value, _buildProvidePayload(objects));
      }
    } catch(e) {
      MyLogger.warn('$logPrefix Failed to handle queryAppType: $e');
    }
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
      if(!_verifyUncipherMessageWithSenderPublicKey(uncipherMessage.data, uncipherMessage.signature, senderPublicKey)) {
        MyLogger.warn('$logPrefix Failed to verify publishAppType signature for sender $senderPublicKey');
        return;
      }
      final uncipherData = uncipherMessage.data;
      final brdMsg = BroadcastMessages.fromJson(jsonDecode(uncipherData));
      final ownerPublicKey = brdMsg.userPublicId;
      if(!_verifyUncipherMessageWithSenderPublicKey(brdMsg.toSignableString(), brdMsg.signature, ownerPublicKey)) {
        MyLogger.warn('$logPrefix Failed to verify publishAppType signature for owner $ownerPublicKey');
        return;
      }
      final messages = brdMsg.messages;
      if(messages.isNotEmpty) {  final latestVersion = messages[latestVersionKey];
        if(latestVersion != null) {
          final latestVersionTimestamp = int.tryParse(messages[latestVersionTimestampKey]?.toString() ?? '');
          final oldLatestVersion = _serverDb.getLatestVersion(ownerPublicKey, latestVersionKey);
          final oldLatestPublishVersionTimestamp = _serverDb.getLatestPublishVersionTimestamp(ownerPublicKey);
          // The publish timestamp is only a hint that says which version_tree timestamp the peer has.
          // Do not store it as the relay cache timestamp; compare it with the stored version_tree resource timestamp instead.
          final versionTreeTimestamp = _serverDb.getVersionTreeTimestamp(ownerPublicKey);
          final hasLatestVersionObject = _serverDb.hasObject(ownerPublicKey, latestVersion);
          final samePublishVersion = oldLatestVersion == latestVersion && (latestVersionTimestamp == null || oldLatestPublishVersionTimestamp == latestVersionTimestamp);
          MyLogger.info('$logPrefix Publish latest_version received: user=$ownerPublicKey, node=${_nodeLabel(node)}, latest_version=$latestVersion, publish_timestamp=$latestVersionTimestamp, old_latest_version=$oldLatestVersion, old_publish_timestamp=$oldLatestPublishVersionTimestamp, same_publish_version=$samePublishVersion, stored_version_tree_timestamp=$versionTreeTimestamp, has_latest_version_object=$hasLatestVersionObject');
          _serverDb.saveLatestVersion(
            ownerPublicKey,
            latestVersionKey,
            latestVersion,
            DateTime.now().millisecondsSinceEpoch,
          );
          _serverDb.saveLatestPublishPayload(ownerPublicKey, latestVersion, latestVersionTimestamp, uncipherData, DateTime.now().millisecondsSinceEpoch);
          if(_shouldRequestVersionTree(latestVersionTimestamp, versionTreeTimestamp)) {
            _sendVersionTreeQuery(appName, node, ownerPublicKey, latestVersionTimestamp, versionTreeTimestamp);
          }
          if(samePublishVersion && latestVersionTimestamp != null && versionTreeTimestamp == latestVersionTimestamp) {
            MyLogger.info('$logPrefix Latest version unchanged for user $ownerPublicKey and version tree timestamp matches publish timestamp. Skip sending offer.');
            if(_serverDb.hasObject(ownerPublicKey, latestVersion)) {
              _forwardPublishToSameUserNodes(ownerPublicKey, uncipherData, sourceNode: node);
              _lastForwardedLatestVersionByUser[ownerPublicKey] = latestVersion;
            }
            return;
          }
          if(!hasLatestVersionObject) {
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
      if(!_verifyUncipherMessage(uncipherMessage)) {
        MyLogger.warn('$logPrefix Failed to verify applyAppType signature for user $userPublicKey');
        return;
      }
      final applyObj = Apply.fromJson(jsonDecode(uncipherMessage.data));
      if(applyObj.type != applyTypeVersion) {
        MyLogger.info('$logPrefix Ignore unsupported apply type: ${applyObj.type}');
        return;
      }
      final versionHashes = _stringListFromApplyData(applyObj.data[applyTypeVersionsKey]);
    
      final List<String> missingVersions = [];
      for(final version in versionHashes) {
        if(!_serverDb.hasObject(userPublicKey, version)) {
          missingVersions.add(version);
        }
      }
      _pendingMissingVersionsByUser[userPublicKey] = missingVersions;
      MyLogger.info('$logPrefix Total versions in apply: ${versionHashes.length}, missing: ${missingVersions.length}');
      _sendNextMissingVersionQuery(userPublicKey, appName, node);
    } catch(e) {
      MyLogger.warn('$logPrefix Failed to handle applyAppType: $e');
    }
  }

  String _buildQueryPayload(List<String> keys) {
    final requireVersions = RequireVersions(requiredVersions: keys);
    final data = jsonEncode(requireVersions);
    final uncipherMessage = UncipherMessage(
      userPublicId: _signing.getCompressedPublicKey(),
      data: data,
      signature: _signing.sign(HashUtil.hashText(data)),
    );
    return jsonEncode(uncipherMessage);
  }

  String _buildProvidePayload(List<CipherMessage> resources) {
    final feature = CipherMessages.getFeature(resources);
    final cipherMessages = CipherMessages(
      userPublicId: _signing.getCompressedPublicKey(),
      resources: resources,
      signature: _signing.sign(HashUtil.hashText(feature)),
    );
    return jsonEncode(cipherMessages);
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

  void _sendVersionTreeQuery(String appName, VillagerNode node, String userPublicKey, int? publishTimestamp, int? storedVersionTreeTimestamp) {
    MyLogger.info('$logPrefix Query version_tree from publish source: user=$userPublicKey, node=${_nodeLabel(node)}, publish_timestamp=$publishTimestamp, stored_version_tree_timestamp=$storedVersionTreeTimestamp');
    final queryPayload = _buildQueryPayload([resourceKeyVersionTree]);
    _overlay.sendData(appName, this, node, AppMessageType.queryAppType.value, queryPayload);
  }

  void _sendNextMissingVersionQuery(String userPublicKey, String appName, VillagerNode node) {
    final pending = _pendingMissingVersionsByUser[userPublicKey];
    if(pending == null || pending.isEmpty) {
      _pendingMissingVersionsByUser.remove(userPublicKey);
      return;
    }
    pending.removeWhere((version) => _serverDb.hasObject(userPublicKey, version));
    if(pending.isEmpty) {
      _pendingMissingVersionsByUser.remove(userPublicKey);
      MyLogger.info('$logPrefix All pending versions cached for user $userPublicKey.');
      return;
    }
    final batchSize = pending.length < maxQueryVersionsPerApply? pending.length : maxQueryVersionsPerApply;
    final queryVersions = pending.sublist(0, batchSize);
    pending.removeRange(0, batchSize);
    if(pending.isEmpty) {
      _pendingMissingVersionsByUser.remove(userPublicKey);
    }
    final pendingTotalAfterSend = _pendingMissingVersionsByUser.values.fold<int>(0, (total, versions) => total + versions.length);
    MyLogger.info('$logPrefix Query missing versions for user $userPublicKey: query_now=${queryVersions.length}, pending_for_user_after_send=${pending.length}, pending_total_after_send=$pendingTotalAfterSend, pending_users=${_pendingMissingVersionsByUser.length}');
    final queryPayload = _buildQueryPayload(queryVersions);
    _overlay.sendData(appName, this, node, AppMessageType.queryAppType.value, queryPayload);
  }

  void _forwardStoredLatestPublishIfReady(String userPublicKey, {VillagerNode? sourceNode}) {
    final latestVersion = _serverDb.getLatestVersion(userPublicKey, latestVersionKey);
    if(latestVersion == null) {
      MyLogger.info('$logPrefix Skip forwarding stored publish for user $userPublicKey: no latest_version cached.');
      return;
    }
    if(!_serverDb.hasObject(userPublicKey, latestVersion)) {
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

  void _broadcastLatestPublishesToSameUserNodes() {
    final records = _serverDb.getLatestPublishPayloads();
    MyLogger.info('$logPrefix Periodic publish forwarding tick: cached_publish_users=${records.length}, interval=${publishIntervalSeconds}s');
    for(final record in records) {
      if(!_serverDb.hasObject(record.userPublicKey, record.latestVersion)) {
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

  bool _verifyUncipherMessageWithSenderPublicKey(String message, String signature, String senderPublicKey) {
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
      _publishTimer = Timer.periodic(Duration(seconds: publishIntervalSeconds), (_) => _broadcastLatestPublishesToSameUserNodes());
      MyLogger.info('$logPrefix Started periodic publish forwarding: interval=${publishIntervalSeconds}s');
    }
    MyLogger.info('$logPrefix Started relay application overlay.');
  }
}
