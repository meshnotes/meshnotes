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

class RelayApplication implements ApplicationController {
  static const logPrefix = '[RelayApplication]';
  static const versionTreeKey = 'version_tree';
  static const latestVersionKey = 'latest_version';
  static const latestVersionTimestampKey = 'latest_version_timestamp';
  final VillageOverlay _overlay;
  final ServerDbHelper _serverDb;
  final SigningWrapper _signing;
  final String upperAppName;
  final Map<String, AppMessageType> _mapOfAppMessageType = {};

  RelayApplication({
    required VillageOverlay overlay,
    required VillageDbHelper db,
    required ServerDbHelper serverDb,
    required SigningWrapper signing,
    required this.upperAppName,
  })  : _overlay = overlay, _serverDb = serverDb, _signing = signing {
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
        MyLogger.info('$logPrefix Received provideAppType data. Storing/Handling...');
        try {
          final decoded = jsonDecode(data);
          final cipherMessages = CipherMessages.fromJson(decoded);
          final userPublicKey = cipherMessages.userPublicId;

          for(var resource in cipherMessages.resources) {
            _serverDb.saveObject(
              userPublicKey: userPublicKey,
              key: resource.key,
              subKey: resource.subKey,
              timestamp: resource.timestamp,
              data: resource.data,
              signature: resource.signature,
              envelope: data,
            );
          }
        } catch(e) {
          MyLogger.warn('$logPrefix Failed to parse provideAppType data: $e');
        }
        break;
      case AppMessageType.queryAppType:
        MyLogger.info('$logPrefix Received queryAppType data.');
        try {
          final decoded = jsonDecode(data);
          final uncipherMessage = UncipherMessage.fromJson(decoded);
          final userPublicKey = uncipherMessage.userPublicId;
          final requireVersions = RequireVersions.fromJson(jsonDecode(uncipherMessage.data));
          final keys = requireVersions.requiredVersions;

          final envelopes = _serverDb.getEnvelopes(userPublicKey, keys);
          MyLogger.info('$logPrefix Found ${envelopes.length} envelopes for user $userPublicKey');
          for(var envelope in envelopes) {
            _overlay.sendData(appName, this, node, AppMessageType.provideAppType.value, envelope);
          }
        } catch(e) {
          MyLogger.warn('$logPrefix Failed to handle queryAppType: $e');
        }
        break;
      case AppMessageType.publishAppType:
        MyLogger.info('$logPrefix Received publishAppType data. Storing/Handling...');
        try {
          final decoded = jsonDecode(data);
          final uncipherMessage = UncipherMessage.fromJson(decoded);
          final userPublicKey = uncipherMessage.userPublicId;
          final dataMap = jsonDecode(uncipherMessage.data) as Map<String, dynamic>;
          final messages = dataMap['messages'] as Map<String, dynamic>?;
          if(messages != null) {
            final latestVersion = messages[latestVersionKey] as String?;
            if(latestVersion != null) {
              final latestVersionTimestamp = int.tryParse(messages[latestVersionTimestampKey]?.toString() ?? '');
              final oldLatestVersion = _serverDb.getLatestVersion(userPublicKey, latestVersionKey);
              // The publish timestamp is only a hint that says which version_tree timestamp the peer has.
              // Do not store it as the relay cache timestamp; compare it with the stored version_tree resource timestamp instead.
              final versionTreeTimestamp = _serverDb.getObjectTimestamp(userPublicKey, versionTreeKey);
              _serverDb.saveLatestVersion(
                userPublicKey,
                latestVersionKey,
                latestVersion,
                DateTime.now().millisecondsSinceEpoch,
              );
              if(oldLatestVersion == latestVersion && latestVersionTimestamp != null && versionTreeTimestamp == latestVersionTimestamp) {
                MyLogger.info('$logPrefix Latest version unchanged for user $userPublicKey and version tree timestamp matches publish timestamp. Skip sending offer.');
                break;
              }
              if(!_serverDb.hasObject(userPublicKey, latestVersion)) {
                final offer = Offer(
                  type: offerTypeStorage,
                  target: userPublicKey,
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
                MyLogger.info('$logPrefix Missing version $latestVersion$timestampText for user $userPublicKey.'
                    ' Sending offer(type=$offerTypeStorage) to ${node.nodeId}.');
                _overlay.sendData(appName, this, node, AppMessageType.offerAppType.value, offerPayload);
              }
            }
          }
          // TODO: Before re-enabling publish relay, record which latest_version values have already been forwarded to avoid relay storms.
        } catch(e) {
          MyLogger.warn('$logPrefix Failed to handle publishAppType: $e');
        }
        break;
      case AppMessageType.applyAppType:
        MyLogger.info('$logPrefix Received applyAppType data. Processing apply...');
        try {
          final decoded = jsonDecode(data);
          final uncipherMessage = UncipherMessage.fromJson(decoded);
          final userPublicKey = uncipherMessage.userPublicId;
          if(!_verifyUncipherMessage(uncipherMessage)) {
            MyLogger.warn('$logPrefix Failed to verify applyAppType signature for user $userPublicKey');
            break;
          }
          final applyObj = Apply.fromJson(jsonDecode(uncipherMessage.data));
          if(applyObj.type != applyTypeVersion) {
            MyLogger.info('$logPrefix Ignore unsupported apply type: ${applyObj.type}');
            break;
          }
          final versionHashes = _stringListFromApplyData(applyObj.data[applyTypeVersionsKey]);

          final List<String> missingVersions = [];
          for(final version in versionHashes) {
            if(!_serverDb.hasObject(userPublicKey, version)) {
              missingVersions.add(version);
            }
          }
          MyLogger.info('$logPrefix Total versions in apply: ${versionHashes.length}, missing: ${missingVersions.length}');
          if(missingVersions.isNotEmpty) {
            // 8) Query missing versions after apply, then reuse the provide flow to store them on the server.
            final queryPayload = _buildQueryPayload(missingVersions);
            _overlay.sendData(appName, this, node, AppMessageType.queryAppType.value, queryPayload);
          }
        } catch(e) {
          MyLogger.warn('$logPrefix Failed to handle applyAppType: $e');
        }
        break;
      case AppMessageType.offerAppType:
        // Normally server is the one sending offers, ignore if received
        break;
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

  Future<void> start() async {
    await _overlay.start();
    MyLogger.info('$logPrefix Started relay application overlay.');
  }
}
