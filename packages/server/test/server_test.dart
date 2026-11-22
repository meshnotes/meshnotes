import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/application/version_chain_api.dart';
import 'package:libp2p/overlay/overlay_controller.dart';
import 'package:libp2p/dal/village_db.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:my_log/my_log.dart';
import 'package:server/relay_application.dart';
import 'package:server/server_db.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

class MockVillageOverlay extends VillageOverlay {
  final List<VillagerNode> mockNodes = [];
  final List<Map<String, dynamic>> sentData = [];

  MockVillageOverlay(): super(
    userInfo: UserPublicInfo(publicKey: 'mock', userName: 'mock', timestamp: 0),
    sponsors: [],
    onNodeChanged: (_){},
  );

  @override
  List<VillagerNode> getAllNodes() => mockNodes;

  @override
  void sendData(String appKey, ApplicationController app, VillagerNode node, String type, String data) {
    sentData.add({
      'appKey': appKey,
      'node': node,
      'type': type,
      'data': data,
    });
  }

  @override
  Future<void> start() async {}
}

UncipherMessage _signedBroadcast(SigningWrapper signing, Map<String, String> messages) {
  final broadcast = BroadcastMessages(
    type: versionChainBroadcastType,
    userPublicId: signing.getCompressedPublicKey(),
    signature: '',
    messages: messages,
  );
  broadcast.signature = signing.sign(HashUtil.hashText(broadcast.toSignableString()));
  final data = jsonEncode(broadcast);
  return UncipherMessage(
    userPublicId: signing.getCompressedPublicKey(),
    data: data,
    signature: signing.sign(HashUtil.hashText(data)),
  );
}

String _signedTransaction(SigningWrapper signing, String data, String id, TransactionContentType type,
    {TransactionStatus status = TransactionStatus.request, int? count}) {
  final message = TransactionMessage(transactionId: id, status: status, contentType: type, data: data,
    userPublicId: signing.getCompressedPublicKey(), signature: '', objectCount: count);
  message.signature = signing.sign(HashUtil.hashText(message.toSignableString()));
  return jsonEncode(message);
}

UncipherMessage _readQuery(dynamic data) {
  final decoded = jsonDecode(data as String) as Map<String, dynamic>;
  return TransactionMessage.isTransaction(decoded) ? TransactionMessage.fromJson(decoded).parseUncipher() : UncipherMessage.fromJson(decoded);
}

String _signedProvide(SigningWrapper signing, CipherMessages message, {String? transactionId,
    bool complete = true, int? count, bool failed = false, bool invalidResource = false}) {
  message.userPublicId = signing.getCompressedPublicKey();
  for(final resource in message.resources) {
    final raw = UnsignedResource(key: resource.key, subKey: resource.subKey, timestamp: resource.timestamp, data: resource.data);
    resource.signature = signing.sign(HashUtil.hashText(raw.getFeature()));
  }
  if(invalidResource) {
    message.resources.first.signature = 'invalid-resource-signature';
  }
  message.signature = signing.sign(HashUtil.hashText(message.getSignableFeature()));
  if(transactionId == null) return jsonEncode(message);
  return _signedTransaction(signing, jsonEncode(message), transactionId, TransactionContentType.cipher,
    status: failed ? TransactionStatus.failed : complete ? TransactionStatus.completed : TransactionStatus.partial,
    count: count ?? (complete ? message.resources.length : null));
}

void main() {
  MyLogger.initForConsoleTest(name: 'server_test', debug: true);
  late Directory tempDir;
  late ServerDbHelper dbHelper;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('server_db_test_');
    dbHelper = ServerDbHelper();
    await dbHelper.init(tempDir.path);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('query responses reuse resources and sign transaction completion including empty and failure', () {
    final signing = SigningWrapper.random();
    final verifier = VerifyingWrapper.loadKey(signing.getCompressedPublicKey());
    final resources = [CipherMessage(key: 'v1', subKey: '', timestamp: 1, data: 'encrypted', signature: 'owner')];
    for(final list in [resources, <CipherMessage>[]]) {
      final payload = CipherMessages.queryResponse(signing.getCompressedPublicKey(), list);
      expect(payload.resources, same(list));
      expect(payload.toJson().containsKey('transaction_id'), isFalse);
    }
    expect(RequireVersions(requiredVersions: ['v1']).toJson(), {'versions': ['v1']});
    for(final type in TransactionContentType.values) {
      final payload = type == TransactionContentType.cipher
        ? jsonEncode(CipherMessages.queryResponse(signing.getCompressedPublicKey(), resources))
        : jsonEncode(UncipherMessage(userPublicId: signing.getCompressedPublicKey(), data: '{"versions":["v1"]}', signature: 'inner'));
      for(final status in TransactionStatus.values) {
        final encoded = _signedTransaction(signing, payload, 'tx', type, status: status,
          count: status == TransactionStatus.completed ? 1 : null);
        final decoded = TransactionMessage.fromJson(jsonDecode(encoded));
        expect(verifier.ver(HashUtil.hashText(decoded.toSignableString()), decoded.signature), isTrue);
        final feature = decoded.toSignableString();
        decoded.signature = 'changed';
        expect(decoded.toSignableString(), feature);
        if(type == TransactionContentType.cipher) {
          expect(decoded.parseCipher().resources.single.key, 'v1');
          expect(() => decoded.parseUncipher(), throwsFormatException);
        } else {
          expect(decoded.parseUncipher().signature, 'inner');
          expect(() => decoded.parseCipher(), throwsFormatException);
        }
        for(final change in <String, dynamic>{'transaction_id': 'other', 'status': status == TransactionStatus.failed ? 'partial' : 'failed',
            'content_type': type == TransactionContentType.cipher ? 'uncipher' : 'cipher', 'data': '$payload ',
            'object_count': status == TransactionStatus.request ? null : 99, 'user': 'other'}.entries) {
          if(change.key == 'object_count' && status == TransactionStatus.request) continue;
          final tampered = (jsonDecode(encoded) as Map<String, dynamic>)..[change.key] = change.value;
          expect(verifier.ver(HashUtil.hashText(TransactionMessage.fromJson(tampered).toSignableString()), jsonDecode(encoded)['sign']), isFalse);
        }
        for(final field in ['status', 'content_type']) {
          final invalid = (jsonDecode(encoded) as Map<String, dynamic>)..[field] = 'unknown';
          expect(() => TransactionMessage.fromJson(invalid), throwsFormatException);
        }
      }
    }
    final generic = _signedTransaction(signing, jsonEncode(UncipherMessage(userPublicId: signing.getCompressedPublicKey(),
      data: 'done', signature: 'inner')), 'generic', TransactionContentType.uncipher, status: TransactionStatus.completed);
    expect(TransactionMessage.fromJson(jsonDecode(generic)).objectCount, isNull);
    for(final count in [-1, 1.5]) {
      final invalid = {'transaction_id': 'tx', 'status': 'completed', 'content_type': 'cipher', 'data': '{}',
        'user': signing.getCompressedPublicKey(), 'sign': '', 'object_count': count};
      expect(() => TransactionMessage.fromJson(invalid), throwsA(anyOf(isA<FormatException>(), isA<TypeError>())));
    }
  });


  test('ServerDbHelper - saveObject and getObjects', () {
    final user = 'user1';
    final key1 = 'key1';
    final versionTreeKey = resourceKeyVersionTree;

    // Test inserting a normal object
    dbHelper.saveObject(
      userPublicKey: user,
      key: key1,
      subKey: '',
      timestamp: 100,
      data: 'data1',
      signature: 'sig1',
    );

    // Fetch stored cipher object
    var objects = dbHelper.getObjects(user, [key1]);
    expect(objects.length, 1);
    expect(objects[0].data, 'data1');
    expect(objects[0].signature, 'sig1');

    // Test inserting same normal object again: it should NOT update (insert or ignore)
    dbHelper.saveObject(
      userPublicKey: user,
      key: key1,
      subKey: '',
      timestamp: 200,
      data: 'data1_updated',
      signature: 'sig1_updated',
    );

    objects = dbHelper.getObjects(user, [key1]);
    expect(objects.length, 1);
    expect(objects[0].data, 'data1');
    expect(objects[0].signature, 'sig1');

    // Test inserting version_tree: it should upsert (update)
    dbHelper.saveObject(
      userPublicKey: user,
      key: versionTreeKey,
      subKey: '',
      timestamp: 100,
      data: 'dag1',
      signature: 'sig_dag1',
    );

    var versionTree = dbHelper.getObject(user, versionTreeKey);
    expect(versionTree, isNotNull);
    expect(versionTree!.data, 'dag1');
    expect(versionTree.signature, 'sig_dag1');

    dbHelper.saveObject(
      userPublicKey: user,
      key: versionTreeKey,
      subKey: '',
      timestamp: 200,
      data: 'dag2',
      signature: 'sig_dag2',
    );

    versionTree = dbHelper.getObject(user, versionTreeKey);
    expect(versionTree, isNotNull);
    expect(versionTree!.data, 'dag2');
    expect(versionTree.signature, 'sig_dag2');

    dbHelper.saveLatestPublishPayload(user, 'v1', 111, 'publish_env_1', 1000);
    dbHelper.saveLatestPublishPayload(user, 'v2', 222, 'publish_env_2', 2000);
    final publishPayloads = dbHelper.getLatestPublishPayloads();
    expect(publishPayloads.length, 1);
    expect(publishPayloads.first.userPublicKey, user);
    expect(publishPayloads.first.latestVersion, 'v2');
    expect(publishPayloads.first.latestVersionTimestamp, 222);
    expect(dbHelper.getLatestPublishVersionTimestamp(user), 222);
    expect(publishPayloads.first.payload, 'publish_env_2');

    final sqlite = sqlite3.open('${tempDir.path}/${ServerDbHelper.dbFileName}');
    addTearDown(sqlite.dispose);
    final objectColumns = sqlite.select('PRAGMA table_info(objects)').map((row) => row['name'] as String).toSet();
    expect(objectColumns.contains('envelope_data'), isTrue);
    expect(objectColumns.contains('data'), isFalse);
    expect(objectColumns.contains('signature'), isFalse);
    expect(objectColumns.contains('envelope'), isFalse);
    expect(objectColumns.contains('envelope_id'), isFalse);
    final versionTreeColumns = sqlite.select('PRAGMA table_info(version_trees)').map((row) => row['name'] as String).toSet();
    expect(versionTreeColumns.contains('envelope_data'), isTrue);
    expect(sqlite.select("SELECT key FROM objects WHERE key=?", [resourceKeyVersionTree]), isEmpty);
    expect(sqlite.select("SELECT key FROM version_trees WHERE user_public_key=?", [user]).single['key'], resourceKeyVersionTree);
    expect(sqlite.select("SELECT name FROM sqlite_master WHERE type='table' AND name='object_envelopes'"), isEmpty);
  });

  test('RelayApplication - provideAppType, queryAppType and publishAppType', () async {
    final mockOverlay = MockVillageOverlay();
    final villageDb = VillageDbHelper();
    await villageDb.init(tempDir.path);
    final signing = SigningWrapper.random();

    final app = RelayApplication(
      overlay: mockOverlay,
      db: villageDb,
      serverDb: dbHelper,
      signing: signing,
      upperAppName: 'mesh_notes',
    );

    final node = VillagerNode(host: '127.0.0.1', port: 8080);
    node.nodeId = 'node_1';

    // 1. Send provideAppType
    final resource1 = CipherMessage(
      key: 'key1',
      subKey: '',
      timestamp: 100,
      data: 'encrypted_data1',
      signature: 'sig1',
    );
    final resourcesList = CipherMessages(
      userPublicId: 'user1',
      resources: [resource1],
      signature: 'outer_sig',
    );
    node.publicKey = signing.getCompressedPublicKey();
    final providePayload = _signedProvide(signing, resourcesList);

    app.onData(node, 'mesh_notes', AppMessageType.provideAppType.value, providePayload);

    // Verify it is saved in DB as a single cipher resource, not the full provide envelope
    final storedObjects = dbHelper.getObjects(node.publicKey, ['key1']);
    expect(storedObjects.length, 1);
    expect(storedObjects.first.data, 'encrypted_data1');
    expect(storedObjects.first.signature, resource1.signature);

    // 2. Send queryAppType
    final requireVersions = RequireVersions(requiredVersions: ['key1']);
    final uncipherQuery = UncipherMessage(
      userPublicId: node.publicKey,
      data: jsonEncode(requireVersions),
      signature: signing.sign(HashUtil.hashText(jsonEncode(requireVersions))),
    );
    final queryPayload = jsonEncode(uncipherQuery);

    app.onData(node, 'mesh_notes', AppMessageType.queryAppType.value, queryPayload);

    // Verify mockOverlay sent a new server-signed provide payload with original cipher resources
    expect(mockOverlay.sentData.length, 1);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.provideAppType.value);
    final returnedProvide = CipherMessages.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
    expect(returnedProvide.userPublicId, signing.getCompressedPublicKey());
    expect(VerifyingWrapper.loadKey(signing.getCompressedPublicKey()).ver(HashUtil.hashText(CipherMessages.getFeature(returnedProvide.resources)), returnedProvide.signature), isTrue);
    expect(returnedProvide.resources.length, 1);
    expect(returnedProvide.resources.first.key, resource1.key);
    expect(returnedProvide.resources.first.data, resource1.data);
    expect(returnedProvide.resources.first.signature, resource1.signature);
    expect(mockOverlay.sentData[0]['node'], node);

    // 3. Send publishAppType
    mockOverlay.sentData.clear();
    final node2 = VillagerNode(host: '127.0.0.1', port: 9090);
    node2.nodeId = 'node_2';
    mockOverlay.mockNodes.addAll([node, node2]);

    final serverUser = signing.getCompressedPublicKey();
    node.publicKey = serverUser;
    final uncipherPublish = _signedBroadcast(signing, {
      'latest_version': 'latest_version_hash_123',
      'latest_version_timestamp': '123456',
    });
    final publishPayload = jsonEncode(uncipherPublish);

    // Send publish from node (node_1)
    app.onData(node, 'mesh_notes', AppMessageType.publishAppType.value, publishPayload);

    expect(dbHelper.getLatestVersion(serverUser, 'latest_version'), isNull);
    final pendingClaim = dbHelper.getPendingClaim(serverUser);
    expect(pendingClaim!.claimedVersion, 'latest_version_hash_123');
    expect(pendingClaim.claimedTimestamp, 123456);

    // Verify publish is not relayed to node2, and server queries version_tree plus sends an offer(type=storage) to the sender.
    expect(mockOverlay.sentData.length, 2);
    expect(mockOverlay.sentData[0]['node'], node);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.queryAppType.value);
    final versionTreeQuery = _readQuery(mockOverlay.sentData[0]['data']);
    final versionTreeRequired = RequireVersions.fromJson(jsonDecode(versionTreeQuery.data));
    final treeTransactionId = TransactionMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'])).transactionId;
    expect(versionTreeRequired.requiredVersions, [resourceKeyVersionTree]);
    expect(mockOverlay.sentData[1]['node'], node);
    expect(mockOverlay.sentData[1]['type'], AppMessageType.offerAppType.value);
    final offerMsg = UncipherMessage.fromJson(jsonDecode(mockOverlay.sentData[1]['data'] as String));
    expect(offerMsg.userPublicId, signing.getCompressedPublicKey());
    final offer = Offer.fromJson(jsonDecode(offerMsg.data));
    expect(offer.type, offerTypeStorage);
    expect(offer.target, serverUser);
    final offerData = offer.data;
    expect(offerData['limit'], 100);

    // Client responds with apply
    mockOverlay.sentData.clear();
    final apply = Apply(
      type: applyTypeVersion,
      data: {
        'versions': [resourceKeyVersionTree],
      },
    );
    final applyData = jsonEncode(apply);
    final uncipherApply = UncipherMessage(
      userPublicId: serverUser,
      data: applyData,
      signature: signing.sign(HashUtil.hashText(applyData)),
    );
    app.onData(node, 'mesh_notes', AppMessageType.applyAppType.value, jsonEncode(uncipherApply));

    // The publish's tree query still occupies this connection; apply must not send another.
    expect(mockOverlay.sentData, isEmpty);
    final queryAfterApply = versionTreeQuery;
    expect(queryAfterApply.userPublicId, signing.getCompressedPublicKey());
    expect(VerifyingWrapper.loadKey(queryAfterApply.userPublicId).ver(HashUtil.hashText(queryAfterApply.data), queryAfterApply.signature), isTrue);
    final requiredAfterApply = RequireVersions.fromJson(jsonDecode(queryAfterApply.data));
    expect(requiredAfterApply.requiredVersions, [resourceKeyVersionTree]);

    mockOverlay.sentData.clear();
    dbHelper.saveObject(
      userPublicKey: serverUser,
      key: resourceKeyVersionTree,
      subKey: '',
      timestamp: 123456,
      data: 'encrypted_tree',
      signature: 'tree_sig',
    );
    dbHelper.saveObject(
      userPublicKey: serverUser,
      key: resourceKeyVersionTree,
      subKey: 'ignored_for_version_tree',
      timestamp: 123456,
      data: 'encrypted_tree_newer',
      signature: 'tree_sig_newer',
    );
    final versionTreeRequire = RequireVersions(requiredVersions: [resourceKeyVersionTree]);
    final versionTreeRequireData = jsonEncode(versionTreeRequire);
    final versionTreeQueryPayload = jsonEncode(UncipherMessage(
      userPublicId: serverUser,
      data: versionTreeRequireData,
      signature: signing.sign(HashUtil.hashText(versionTreeRequireData)),
    ));
    app.onData(node, 'mesh_notes', AppMessageType.queryAppType.value, versionTreeQueryPayload);
    expect(mockOverlay.sentData.length, 1);
    expect(mockOverlay.sentData[0]['node'], node);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.provideAppType.value);
    final returnedVersionTree = CipherMessages.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
    expect(returnedVersionTree.userPublicId, signing.getCompressedPublicKey());
    expect(VerifyingWrapper.loadKey(signing.getCompressedPublicKey()).ver(HashUtil.hashText(CipherMessages.getFeature(returnedVersionTree.resources)), returnedVersionTree.signature), isTrue);
    expect(returnedVersionTree.resources.length, 1);
    expect(returnedVersionTree.resources.first.key, resourceKeyVersionTree);
    expect(returnedVersionTree.resources.first.data, 'encrypted_tree_newer');
    expect(returnedVersionTree.resources.first.signature, 'tree_sig_newer');

    final committedTree = CipherMessages(
      userPublicId: serverUser,
      resources: [
        CipherMessage(key: resourceKeyVersionTree, subKey: 'latest_version_hash_123', timestamp: 123456, data: 'encrypted_tree_committed', signature: ''),
      ],
      signature: '',
    );
    app.onData(node, 'mesh_notes', AppMessageType.provideAppType.value, _signedProvide(signing, committedTree, transactionId: treeTransactionId));
    expect(dbHelper.getLatestVersion(serverUser, 'latest_version'), 'latest_version_hash_123');
    expect(dbHelper.getLatestVersionTimestamp(serverUser, 'latest_version'), isNotNull);
    expect(dbHelper.getLatestPublishVersionTimestamp(serverUser), 123456);

    mockOverlay.sentData.clear();
    app.onData(node, 'mesh_notes', AppMessageType.publishAppType.value, publishPayload);
    expect(mockOverlay.sentData.single['type'], AppMessageType.offerAppType.value); // Missing version object must still be repaired.

    mockOverlay.sentData.clear();
    dbHelper.saveObject(
      userPublicKey: serverUser,
      key: 'already_cached_version_hash',
      subKey: '',
      timestamp: 200,
      data: 'cached_data',
      signature: 'cached_sig',
    );
    final cachedPublish = _signedBroadcast(signing, {'latest_version': 'already_cached_version_hash'});
    app.onData(node, 'mesh_notes', AppMessageType.publishAppType.value, jsonEncode(cachedPublish));

    expect(mockOverlay.sentData.single['type'], AppMessageType.publishAppType.value); // A different cached version still conflicts.
    expect(dbHelper.getLatestVersion(serverUser, 'latest_version'), 'latest_version_hash_123');

    mockOverlay.sentData.clear();
    final otherUserSigning = SigningWrapper.random();
    final otherUserPublicKey = otherUserSigning.getCompressedPublicKey();
    node.publicKey = otherUserPublicKey;
    final otherUserPublish = _signedBroadcast(otherUserSigning, {'latest_version': 'other_user_version_hash'});
    app.onData(node, 'mesh_notes', AppMessageType.publishAppType.value, jsonEncode(otherUserPublish));

    expect(dbHelper.getLatestVersion(otherUserPublicKey, 'latest_version'), isNull);
    expect(dbHelper.getPendingClaim(otherUserPublicKey)!.claimedVersion, 'other_user_version_hash');
    expect(mockOverlay.sentData.length, 2);
    expect(mockOverlay.sentData[0]['node'], node);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.queryAppType.value);
    final otherUserVersionTreeQuery = _readQuery(mockOverlay.sentData[0]['data']);
    final otherUserVersionTreeRequired = RequireVersions.fromJson(jsonDecode(otherUserVersionTreeQuery.data));
    expect(otherUserVersionTreeRequired.requiredVersions, [resourceKeyVersionTree]);
    expect(mockOverlay.sentData[1]['node'], node);
    expect(mockOverlay.sentData[1]['type'], AppMessageType.offerAppType.value);
    final otherUserOfferMsg = UncipherMessage.fromJson(jsonDecode(mockOverlay.sentData[1]['data'] as String));
    expect(otherUserOfferMsg.userPublicId, signing.getCompressedPublicKey());
    final otherUserOffer = Offer.fromJson(jsonDecode(otherUserOfferMsg.data));
    expect(otherUserOffer.type, offerTypeStorage);
    expect(otherUserOffer.target, otherUserPublicKey);
    final otherUserOfferData = otherUserOffer.data;
    expect(otherUserOfferData['limit'], 100);

    // Respond with apply for other_user
    mockOverlay.sentData.clear();
    final otherUserApply = Apply(
      type: applyTypeVersion,
      data: {
        'versions': [resourceKeyVersionTree],
      },
    );
    final otherUserApplyData = jsonEncode(otherUserApply);
    final otherUserUncipherApply = UncipherMessage(
      userPublicId: otherUserPublicKey,
      data: otherUserApplyData,
      signature: otherUserSigning.sign(HashUtil.hashText(otherUserApplyData)),
    );
    app.onData(node, 'mesh_notes', AppMessageType.applyAppType.value, jsonEncode(otherUserUncipherApply));

    expect(mockOverlay.sentData, isEmpty);
    final otherUserQuery = otherUserVersionTreeQuery;
    expect(otherUserQuery.userPublicId, signing.getCompressedPublicKey());
    expect(VerifyingWrapper.loadKey(otherUserQuery.userPublicId).ver(HashUtil.hashText(otherUserQuery.data), otherUserQuery.signature), isTrue);
    final otherUserRequired = RequireVersions.fromJson(jsonDecode(otherUserQuery.data));
    expect(otherUserRequired.requiredVersions, [resourceKeyVersionTree]);
  });

  for(final scenario in ['out-of-order', 'empty', 'failed', 'timeout', 'bad-signature', 'invalid-resource', 'wrong-peer', 'save-failure', 'reapply', 'tree-first', 'reconnect', 'count-mismatch', 'missing-key', 'missing-end', 'partial-timeout', 'two-connections', 'missing-count', 'wrong-status', 'wrong-content']) {
    test('RelayApplication - transaction flow $scenario', () async {
      final overlay = MockVillageOverlay();
      final villageDb = VillageDbHelper();
      await villageDb.init(tempDir.path);
      final signing = SigningWrapper.random();
      final user = signing.getCompressedPublicKey();
      final node = VillagerNode(host: '127.0.0.1', port: 8080)..publicKey = user;
      node.setConnected();
      final other = VillagerNode(host: '127.0.0.1', port: 8081)..publicKey = user;
      other.setConnected();
      final app = RelayApplication(overlay: overlay, db: villageDb, serverDb: dbHelper,
        signing: SigningWrapper.random(), upperAppName: 'mesh_notes', maxQueryVersionsPerApply: 1, publishIntervalSeconds: 0);
      final callbacks = <void Function()>[];
      final timers = <Timer>[];
      void timeout() => callbacks[timers.indexWhere((timer) => timer.isActive)]();
      addTearDown(() { for(final timer in timers) { timer.cancel(); } });
      void apply([VillagerNode? target]) {
        final body = jsonEncode(Apply(type: applyTypeVersion, data: {'versions': ['v1', 'v2', 'v1']}));
        app.onData(target ?? node, 'mesh_notes', 'apply', jsonEncode(UncipherMessage(userPublicId: user,
          data: body, signature: signing.sign(HashUtil.hashText(body)))));
      }
      String id() {
        return TransactionMessage.fromJson(jsonDecode(overlay.sentData.lastWhere((item) => item['type'] == 'query')['data'])).transactionId;
      }
      void provide(String tx, List<String> keys, {bool complete = false, int? count, bool failed = false, VillagerNode? from, bool bad = false, bool invalidResource = false}) {
        final message = CipherMessages(userPublicId: user, resources: keys.map((key) =>
          CipherMessage(key: key, subKey: '', timestamp: 1, data: key, signature: '')).toList(), signature: '');
        final payload = _signedProvide(signing, message, transactionId: tx, complete: complete, count: count,
          failed: failed, invalidResource: invalidResource);
        app.onData(from ?? node, 'mesh_notes', 'provide', bad ? payload.replaceFirst('"status":"completed"', '"status":"partial"') : payload);
      }
      runZoned(() {
        if(scenario == 'tree-first') {
          app.onData(node, 'mesh_notes', 'publish', jsonEncode(_signedBroadcast(signing, {'latest_version': 'v1', 'latest_version_timestamp': '1'})));
        }
        apply();
        final first = id();
        expect(first, isNotEmpty);
        final initialQueries = overlay.sentData.where((item) => item['type'] == 'query').length;
        expect(initialQueries, 1);
        if(scenario == 'tree-first') {
          final tree = CipherMessages(userPublicId: user, resources: [CipherMessage(key: resourceKeyVersionTree, subKey: 'v1', timestamp: 1, data: 'tree', signature: '')],
            signature: '');
          app.onData(node, 'mesh_notes', 'provide', _signedProvide(signing, tree, transactionId: first));
          expect(id(), isNot(first));
          return;
        }
        if(scenario == 'two-connections') {
          apply(other);
          final second = id();
          expect(second, isNot(first));
          expect(overlay.sentData.length, 2);
          provide(first, ['v1'], complete: true, count: 1, from: other);
          expect(overlay.sentData.length, 2);
          provide(first, ['v1'], complete: true, count: 1);
          expect(overlay.sentData.last['node'], same(node));
          provide(second, ['v1'], complete: true, count: 1, from: other);
          expect(overlay.sentData.last['node'], same(other));
          expect(overlay.sentData.length, 4);
          return;
        }
        if(scenario == 'reapply') {
          apply();
          expect(id(), first);
          expect(overlay.sentData.length, 1);
        }
        if(scenario == 'wrong-peer') {
          provide(first, ['v1'], complete: true, count: 1, from: other);
          expect(id(), first);
          expect(dbHelper.hasObject(user, 'v1'), isFalse);
        }
        if(scenario == 'reconnect') {
          node.setLost();
          timeout();
          expect(overlay.sentData.length, 1);
          node.setConnected();
          apply();
          expect(id(), isNot(first));
          provide(first, ['v1'], complete: true, count: 1);
          expect(dbHelper.hasObject(user, 'v1'), isFalse);
          return;
        }
        if(['empty', 'failed', 'timeout', 'bad-signature', 'invalid-resource', 'save-failure', 'count-mismatch', 'missing-key', 'missing-end', 'partial-timeout', 'missing-count', 'wrong-status', 'wrong-content'].contains(scenario)) {
          if(['missing-count', 'wrong-status', 'wrong-content'].contains(scenario)) {
            final ordinary = _signedProvide(signing, CipherMessages(userPublicId: user,
              resources: [CipherMessage(key: 'v1', subKey: '', timestamp: 1, data: 'version', signature: '')], signature: ''));
            final payload = _signedTransaction(signing, ordinary, first,
              scenario == 'wrong-content' ? TransactionContentType.uncipher : TransactionContentType.cipher,
              status: scenario == 'wrong-status' ? TransactionStatus.request : TransactionStatus.completed,
              count: scenario == 'wrong-content' ? 1 : null);
            expect(() => app.onData(node, 'mesh_notes', 'provide', payload), returnsNormally);
            expect(dbHelper.hasObject(user, 'v1'), isFalse);
          } else if(scenario == 'save-failure') {
            final sql = sqlite3.open('${tempDir.path}/${ServerDbHelper.dbFileName}');
            sql.execute("CREATE TRIGGER fail_save BEFORE INSERT ON objects BEGIN SELECT RAISE(FAIL, 'test save failure'); END");
            provide(first, ['v1'], complete: true, count: 1);
            expect(dbHelper.hasObject(user, 'v1'), isFalse);
            sql.execute('DROP TRIGGER fail_save');
            sql.dispose();
          } else if(scenario == 'count-mismatch') {
            provide(first, ['dep'], complete: true, count: 2);
            provide(first, [], complete: true, count: 1);
          } else if(scenario == 'missing-key') {
            provide(first, ['dep'], complete: true, count: 1);
          } else if(scenario == 'missing-end' || scenario == 'partial-timeout') {
            provide(first, ['v1']);
          } else if(scenario != 'timeout') {
            provide(first, ['bad-signature', 'invalid-resource'].contains(scenario) ? ['v1'] : [], complete: true,
              count: ['bad-signature', 'invalid-resource'].contains(scenario) ? 1 : 0, failed: scenario == 'failed',
              bad: scenario == 'bad-signature', invalidResource: scenario == 'invalid-resource');
          }
          expect(overlay.sentData.length, 1, reason: 'failure/empty/missing is not successful completion');
          timeout();
          final second = id();
          expect(second, isNot(first));
          provide(first, ['v1'], complete: true, count: 1);
          expect(id(), second, reason: 'stale attempt cannot finish the retry');
          if(scenario == 'timeout') {
            timeout();
            expect(id(), isNot(second));
            final attempts = overlay.sentData.length;
            timeout();
            expect(overlay.sentData.length, attempts, reason: 'retry budget exhausted');
            apply();
            expect(overlay.sentData.length, attempts + 1, reason: 'later handshake can recover');
            return;
          }
          provide(second, ['v1'], complete: true, count: 1);
        } else {
          provide(first, ['dep'], complete: true, count: 2);
          expect(id(), first, reason: 'end marker can arrive before a large version');
          provide(first, ['dep'], complete: true, count: 2);
          expect(id(), first, reason: 'duplicates do not count twice');
          provide(first, ['v1']);
        }
        final next = id();
        expect(next, isNot(first));
        expect(dbHelper.hasObject(user, 'v1'), isTrue);
        expect(overlay.sentData.where((item) => item['type'] == 'query').length,
          ['empty', 'failed', 'bad-signature', 'invalid-resource', 'save-failure', 'count-mismatch', 'missing-key', 'missing-end', 'partial-timeout', 'missing-count', 'wrong-status', 'wrong-content'].contains(scenario) ? 3 : 2);
        provide(first, ['late'], complete: true, count: 1);
        expect(id(), next);
        expect(dbHelper.hasObject(user, 'late'), isFalse);
        provide(next, ['v2'], complete: true, count: 1);
        expect(dbHelper.hasObject(user, 'v2'), isTrue);
      }, zoneSpecification: ZoneSpecification(createTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createTimer(zone, const Duration(days: 1), () {});
        timers.add(timer);
        callbacks.add(() { timer.cancel(); zone.run(callback); });
        return timer;
      }));
    });
  }

  test('RelayApplication - query replies echo signed completion for empty, mixed and failed lookups', () async {
    final overlay = MockVillageOverlay();
    final villageDb = VillageDbHelper();
    await villageDb.init(tempDir.path);
    final signing = SigningWrapper.random();
    final node = VillagerNode(host: '127.0.0.1', port: 8080)..publicKey = signing.getCompressedPublicKey();
    final app = RelayApplication(overlay: overlay, db: villageDb, serverDb: dbHelper,
      signing: signing, upperAppName: 'mesh_notes', publishIntervalSeconds: 0);
    void query(List<String> keys) {
      overlay.sentData.clear();
      final data = jsonEncode(RequireVersions(requiredVersions: keys));
      final payload = jsonEncode(UncipherMessage(userPublicId: node.publicKey,
        data: data, signature: signing.sign(HashUtil.hashText(data))));
      app.onData(node, 'mesh_notes', 'query', _signedTransaction(signing, payload, 'read-1', TransactionContentType.uncipher));
    }
    TransactionMessage response() {
      final message = TransactionMessage.fromJson(jsonDecode(overlay.sentData.single['data']));
      expect(message.transactionId, 'read-1');
      expect(message.status, anyOf(TransactionStatus.completed, TransactionStatus.failed));
      expect(VerifyingWrapper.loadKey(node.publicKey).ver(HashUtil.hashText(message.toSignableString()), message.signature), isTrue);
      return message;
    }
    query(['absent']);
    expect(response().objectCount, 0);
    expect(response().status, TransactionStatus.completed);
    dbHelper.saveObject(userPublicKey: node.publicKey, key: 'v1', subKey: '', timestamp: 1, data: 'v1', signature: 'owner-sign');
    dbHelper.saveVersionTree(userPublicKey: node.publicKey,
      resource: CipherMessage(key: resourceKeyVersionTree, subKey: 'v1', timestamp: 1, data: 'tree', signature: 'tree-owner'));
    query([resourceKeyVersionTree, 'v1', 'v1']);
    expect(response().objectCount, 2);
    expect(response().parseCipher().resources.map((resource) => resource.key).toSet(), {resourceKeyVersionTree, 'v1'});
    final sql = sqlite3.open('${tempDir.path}/${ServerDbHelper.dbFileName}');
    sql.execute('DROP TABLE objects');
    sql.dispose();
    query(['v1']);
    expect(response().objectCount, 0);
    expect(response().status, TransactionStatus.failed);
  });

  test('RelayApplication - ordinary provides cannot fan out an active query', () async {
    final overlay = MockVillageOverlay();
    final villageDb = VillageDbHelper();
    await villageDb.init(tempDir.path);
    final signing = SigningWrapper.random();
    final node = VillagerNode(host: '127.0.0.1', port: 8080)..publicKey = signing.getCompressedPublicKey();
    final app = RelayApplication(overlay: overlay, db: villageDb, serverDb: dbHelper,
      signing: SigningWrapper.random(), upperAppName: 'mesh_notes', maxQueryVersionsPerApply: 1, publishIntervalSeconds: 0);
    final body = jsonEncode(Apply(type: applyTypeVersion, data: {'versions': ['v1', 'v2', 'v3']}));
    app.onData(node, 'mesh_notes', 'apply', jsonEncode(UncipherMessage(userPublicId: node.publicKey,
      data: body, signature: signing.sign(HashUtil.hashText(body)))));
    expect(overlay.sentData.length, 1);
    final resource = CipherMessage(key: 'v1', subKey: '', timestamp: 1, data: 'v1-data', signature: '');
    app.onData(node, 'mesh_notes', 'provide', _signedProvide(signing,
      CipherMessages(userPublicId: node.publicKey, resources: [resource], signature: '')));
    expect(overlay.sentData.length, 1, reason: 'a version provide is not the dependency-bundle completion');
    final query = TransactionMessage.fromJson(jsonDecode(overlay.sentData.single['data']));
    expect(query.transactionId, isNotEmpty);
  });

  test('RelayApplication - limits query versions per apply from config', () async {
    final mockOverlay = MockVillageOverlay();
    final villageDb = VillageDbHelper();
    await villageDb.init(tempDir.path);
    final signing = SigningWrapper.random();
    final userSigning = SigningWrapper.random();
    final userPublicKey = userSigning.getCompressedPublicKey();

    final app = RelayApplication(
      overlay: mockOverlay,
      db: villageDb,
      serverDb: dbHelper,
      signing: signing,
      upperAppName: 'mesh_notes',
      maxQueryVersionsPerApply: 2,
      publishIntervalSeconds: 0,
    );
    final node = VillagerNode(host: '127.0.0.1', port: 8080);
    node.nodeId = 'node_1';

    final apply = Apply(
      type: applyTypeVersion,
      data: {
        'versions': ['v1', 'v2', 'v3'],
      },
    );
    final applyData = jsonEncode(apply);
    final uncipherApply = UncipherMessage(
      userPublicId: userPublicKey,
      data: applyData,
      signature: userSigning.sign(HashUtil.hashText(applyData)),
    );

    node.publicKey = userPublicKey;
    app.onData(node, 'mesh_notes', AppMessageType.applyAppType.value, jsonEncode(uncipherApply));

    expect(mockOverlay.sentData.length, 1);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.queryAppType.value);
    final queryAfterApply = _readQuery(mockOverlay.sentData[0]['data']);
    final requiredAfterApply = RequireVersions.fromJson(jsonDecode(queryAfterApply.data));
    expect(requiredAfterApply.requiredVersions, ['v1', 'v2']);

    final batchTransactionId = TransactionMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'])).transactionId;
    mockOverlay.sentData.clear();
    final providedResources = CipherMessages(
      userPublicId: userPublicKey,
      resources: [
        CipherMessage(key: 'v1', subKey: '', timestamp: 1, data: 'data1', signature: 'sig1'),
        CipherMessage(key: 'v2', subKey: '', timestamp: 2, data: 'data2', signature: 'sig2'),
      ],
      signature: 'provide_sig',
    );
    app.onData(node, 'mesh_notes', AppMessageType.provideAppType.value, _signedProvide(userSigning, providedResources, transactionId: batchTransactionId));

    expect(mockOverlay.sentData.length, 1);
    final nextQuery = _readQuery(mockOverlay.sentData[0]['data']);
    final nextRequired = RequireVersions.fromJson(jsonDecode(nextQuery.data));
    expect(nextRequired.requiredVersions, ['v3']);
  });

  test('RelayApplication - forwards cached publish to same-user nodes after provide', () async {
    final mockOverlay = MockVillageOverlay();
    final villageDb = VillageDbHelper();
    await villageDb.init(tempDir.path);
    final signing = SigningWrapper.random();
    final userSigning = SigningWrapper.random();
    final userPublicKey = userSigning.getCompressedPublicKey();
    final otherSigning = SigningWrapper.random();

    final app = RelayApplication(
      overlay: mockOverlay,
      db: villageDb,
      serverDb: dbHelper,
      signing: signing,
      upperAppName: 'mesh_notes',
      publishIntervalSeconds: 0,
    );
    final sourceNode = VillagerNode(host: '127.0.0.1', port: 8080)
      ..nodeId = 'source'
      ..publicKey = userPublicKey;
    sourceNode.setConnected();
    final sameUserNode = VillagerNode(host: '127.0.0.1', port: 8081)
      ..nodeId = 'same_user'
      ..publicKey = userPublicKey;
    sameUserNode.setConnected();
    final otherUserNode = VillagerNode(host: '127.0.0.1', port: 8082)
      ..nodeId = 'other_user'
      ..publicKey = otherSigning.getCompressedPublicKey();
    otherUserNode.setConnected();
    mockOverlay.mockNodes.addAll([sourceNode, sameUserNode, otherUserNode]);

    final publish = _signedBroadcast(userSigning, {'latest_version': 'v1'});
    final publishPayload = jsonEncode(publish);

    app.onData(sourceNode, 'mesh_notes', AppMessageType.publishAppType.value, publishPayload);
    expect(mockOverlay.sentData.length, 2);
    expect(mockOverlay.sentData[0]['node'], sourceNode);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.queryAppType.value);
    final versionTreeQuery = _readQuery(mockOverlay.sentData[0]['data']);
    final versionTreeRequired = RequireVersions.fromJson(jsonDecode(versionTreeQuery.data));
    final treeTransactionId = TransactionMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'])).transactionId;
    expect(versionTreeRequired.requiredVersions, [resourceKeyVersionTree]);
    expect(mockOverlay.sentData[1]['node'], sourceNode);
    expect(mockOverlay.sentData[1]['type'], AppMessageType.offerAppType.value);

    mockOverlay.sentData.clear();
    final apply = Apply(
      type: applyTypeVersion,
      data: {
        'versions': ['v1'],
      },
    );
    final applyData = jsonEncode(apply);
    final uncipherApply = UncipherMessage(
      userPublicId: userPublicKey,
      data: applyData,
      signature: userSigning.sign(HashUtil.hashText(applyData)),
    );
    app.onData(sourceNode, 'mesh_notes', AppMessageType.applyAppType.value, jsonEncode(uncipherApply));
    expect(mockOverlay.sentData, isEmpty, reason: 'tree query is still in flight');
    expect(dbHelper.getLatestVersion(userPublicKey, 'latest_version'), isNull);
    final versionTree = CipherMessages(userPublicId: userPublicKey,
      resources: [CipherMessage(key: resourceKeyVersionTree, subKey: 'v1', timestamp: 1, data: 'tree-v1', signature: '')],
      signature: '');
    app.onData(sourceNode, 'mesh_notes', AppMessageType.provideAppType.value, _signedProvide(userSigning, versionTree, transactionId: treeTransactionId));
    expect(mockOverlay.sentData.single['type'], AppMessageType.queryAppType.value);
    final versionTransactionId = TransactionMessage.fromJson(jsonDecode(mockOverlay.sentData.single['data'])).transactionId;
    mockOverlay.sentData.clear();
    final providedVersion = CipherMessages(userPublicId: userPublicKey,
      resources: [CipherMessage(key: 'v1', subKey: '', timestamp: 1, data: 'data1', signature: '')],
      signature: '');
    app.onData(sourceNode, 'mesh_notes', AppMessageType.provideAppType.value, _signedProvide(userSigning, providedVersion, transactionId: versionTransactionId, complete: false));
    expect(dbHelper.hasObject(userPublicKey, 'v1'), isTrue);
    expect(mockOverlay.sentData, isEmpty, reason: 'saved version alone does not prove dependencies are ready');
    final dependencies = CipherMessages(userPublicId: userPublicKey,
      resources: [CipherMessage(key: 'dep', subKey: '', timestamp: 1, data: 'dependency', signature: '')],
      signature: '');
    app.onData(sourceNode, 'mesh_notes', AppMessageType.provideAppType.value, _signedProvide(userSigning, dependencies, transactionId: versionTransactionId, count: 2));
    expect(mockOverlay.sentData.length, 1);
    expect(mockOverlay.sentData[0]['node'], sameUserNode);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.publishAppType.value);
    final relayed = _readQuery(mockOverlay.sentData[0]['data']);
    expect(relayed.userPublicId, signing.getCompressedPublicKey());
    expect(VerifyingWrapper.loadKey(relayed.userPublicId).ver(HashUtil.hashText(relayed.data), relayed.signature), isTrue);
    expect(relayed.data, publish.data);
    final relayedBroadcast = BroadcastMessages.fromJson(jsonDecode(relayed.data));
    expect(VerifyingWrapper.loadKey(userPublicKey).ver(HashUtil.hashText(relayedBroadcast.toSignableString()), relayedBroadcast.signature), isTrue);
  });
}
