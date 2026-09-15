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
    final providePayload = jsonEncode(resourcesList);

    app.onData(node, 'mesh_notes', AppMessageType.provideAppType.value, providePayload);

    // Verify it is saved in DB as a single cipher resource, not the full provide envelope
    final storedObjects = dbHelper.getObjects('user1', ['key1']);
    expect(storedObjects.length, 1);
    expect(storedObjects.first.data, 'encrypted_data1');
    expect(storedObjects.first.signature, 'sig1');

    // 2. Send queryAppType
    final requireVersions = RequireVersions(requiredVersions: ['key1']);
    final uncipherQuery = UncipherMessage(
      userPublicId: 'user1',
      data: jsonEncode(requireVersions),
      signature: 'query_sig',
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

    expect(dbHelper.getLatestVersion(serverUser, 'latest_version'), 'latest_version_hash_123');
    expect(dbHelper.getLatestVersionTimestamp(serverUser, 'latest_version'), isNotNull);
    expect(dbHelper.getLatestPublishVersionTimestamp(serverUser), 123456);

    // Verify publish is not relayed to node2, and server queries version_tree plus sends an offer(type=storage) to the sender.
    expect(mockOverlay.sentData.length, 2);
    expect(mockOverlay.sentData[0]['node'], node);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.queryAppType.value);
    final versionTreeQuery = UncipherMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
    final versionTreeRequired = RequireVersions.fromJson(jsonDecode(versionTreeQuery.data));
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

    // Verify server queries the sender for the missing versions
    expect(mockOverlay.sentData.length, 1);
    expect(mockOverlay.sentData[0]['node'], node);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.queryAppType.value);
    final queryAfterApply = UncipherMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
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

    mockOverlay.sentData.clear();
    app.onData(node, 'mesh_notes', AppMessageType.publishAppType.value, publishPayload);
    expect(mockOverlay.sentData, isEmpty);

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

    expect(mockOverlay.sentData, isEmpty);

    mockOverlay.sentData.clear();
    final otherUserSigning = SigningWrapper.random();
    final otherUserPublicKey = otherUserSigning.getCompressedPublicKey();
    node.publicKey = otherUserPublicKey;
    final otherUserPublish = _signedBroadcast(otherUserSigning, {'latest_version': 'other_user_version_hash'});
    app.onData(node, 'mesh_notes', AppMessageType.publishAppType.value, jsonEncode(otherUserPublish));

    expect(dbHelper.getLatestVersion(otherUserPublicKey, 'latest_version'), 'other_user_version_hash');
    expect(mockOverlay.sentData.length, 2);
    expect(mockOverlay.sentData[0]['node'], node);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.queryAppType.value);
    final otherUserVersionTreeQuery = UncipherMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
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

    expect(mockOverlay.sentData.length, 1);
    expect(mockOverlay.sentData[0]['node'], node);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.queryAppType.value);
    final otherUserQuery = UncipherMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
    expect(otherUserQuery.userPublicId, signing.getCompressedPublicKey());
    expect(VerifyingWrapper.loadKey(otherUserQuery.userPublicId).ver(HashUtil.hashText(otherUserQuery.data), otherUserQuery.signature), isTrue);
    final otherUserRequired = RequireVersions.fromJson(jsonDecode(otherUserQuery.data));
    expect(otherUserRequired.requiredVersions, [resourceKeyVersionTree]);
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

    app.onData(node, 'mesh_notes', AppMessageType.applyAppType.value, jsonEncode(uncipherApply));

    expect(mockOverlay.sentData.length, 1);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.queryAppType.value);
    final queryAfterApply = UncipherMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
    final requiredAfterApply = RequireVersions.fromJson(jsonDecode(queryAfterApply.data));
    expect(requiredAfterApply.requiredVersions, ['v1', 'v2']);

    mockOverlay.sentData.clear();
    final providedResources = CipherMessages(
      userPublicId: userPublicKey,
      resources: [
        CipherMessage(key: 'v1', subKey: '', timestamp: 1, data: 'data1', signature: 'sig1'),
        CipherMessage(key: 'v2', subKey: '', timestamp: 2, data: 'data2', signature: 'sig2'),
      ],
      signature: 'provide_sig',
    );
    app.onData(node, 'mesh_notes', AppMessageType.provideAppType.value, jsonEncode(providedResources));

    expect(mockOverlay.sentData.length, 1);
    final nextQuery = UncipherMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
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
    final versionTreeQuery = UncipherMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
    final versionTreeRequired = RequireVersions.fromJson(jsonDecode(versionTreeQuery.data));
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
    expect(mockOverlay.sentData.single['type'], AppMessageType.queryAppType.value);

    mockOverlay.sentData.clear();
    final providedResources = CipherMessages(
      userPublicId: userPublicKey,
      resources: [
        CipherMessage(key: 'v1', subKey: '', timestamp: 1, data: 'data1', signature: 'sig1'),
      ],
      signature: 'provide_sig',
    );
    app.onData(sourceNode, 'mesh_notes', AppMessageType.provideAppType.value, jsonEncode(providedResources));

    expect(mockOverlay.sentData.length, 1);
    expect(mockOverlay.sentData[0]['node'], sameUserNode);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.publishAppType.value);
    final relayed = UncipherMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
    expect(relayed.userPublicId, signing.getCompressedPublicKey());
    expect(VerifyingWrapper.loadKey(relayed.userPublicId).ver(HashUtil.hashText(relayed.data), relayed.signature), isTrue);
    expect(relayed.data, publish.data);
    final relayedBroadcast = BroadcastMessages.fromJson(jsonDecode(relayed.data));
    expect(VerifyingWrapper.loadKey(userPublicKey).ver(HashUtil.hashText(relayedBroadcast.toSignableString()), relayedBroadcast.signature), isTrue);
  });
}
