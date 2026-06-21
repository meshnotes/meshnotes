import 'dart:convert';
import 'dart:io';

import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/overlay/overlay_controller.dart';
import 'package:libp2p/dal/village_db.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:my_log/my_log.dart';
import 'package:server/relay_application.dart';
import 'package:server/server_db.dart';
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

  test('ServerDbHelper - saveObject and getEnvelopes', () {
    final user = 'user1';
    final key1 = 'key1';
    final versionTreeKey = 'version_tree';

    // Test inserting a normal object
    dbHelper.saveObject(
      userPublicKey: user,
      key: key1,
      subKey: '',
      timestamp: 100,
      data: 'data1',
      signature: 'sig1',
      envelope: 'env1',
    );

    // Fetch envelope
    var envs = dbHelper.getEnvelopes(user, [key1]);
    expect(envs.length, 1);
    expect(envs[0], 'env1');

    // Test inserting same normal object again: it should NOT update (insert or ignore)
    dbHelper.saveObject(
      userPublicKey: user,
      key: key1,
      subKey: '',
      timestamp: 200,
      data: 'data1_updated',
      signature: 'sig1_updated',
      envelope: 'env1_updated',
    );

    envs = dbHelper.getEnvelopes(user, [key1]);
    expect(envs.length, 1);
    expect(envs[0], 'env1');

    // Test inserting version_tree: it should upsert (update)
    dbHelper.saveObject(
      userPublicKey: user,
      key: versionTreeKey,
      subKey: '',
      timestamp: 100,
      data: 'dag1',
      signature: 'sig_dag1',
      envelope: 'env_dag1',
    );

    envs = dbHelper.getEnvelopes(user, [versionTreeKey]);
    expect(envs.length, 1);
    expect(envs[0], 'env_dag1');

    dbHelper.saveObject(
      userPublicKey: user,
      key: versionTreeKey,
      subKey: '',
      timestamp: 200,
      data: 'dag2',
      signature: 'sig_dag2',
      envelope: 'env_dag2',
    );

    envs = dbHelper.getEnvelopes(user, [versionTreeKey]);
    expect(envs.length, 1);
    expect(envs[0], 'env_dag2');
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
    final resource1 = SignedResource(
      key: 'key1',
      subKey: '',
      timestamp: 100,
      data: 'encrypted_data1',
      signature: 'sig1',
    );
    final resourcesList = SignedResources(
      userPublicId: 'user1',
      resources: [resource1],
      signature: 'outer_sig',
    );
    final providePayload = jsonEncode(resourcesList);

    app.onData(node, 'mesh_notes', AppMessageType.provideAppType.value, providePayload);

    // Verify it is saved in DB
    final envs = dbHelper.getEnvelopes('user1', ['key1']);
    expect(envs.length, 1);
    expect(jsonDecode(envs[0])['sign'], 'outer_sig');

    // 2. Send queryAppType
    final requireVersions = RequireVersions(requiredVersions: ['key1']);
    final signedQuery = SignedMessage(
      userPublicId: 'user1',
      data: jsonEncode(requireVersions),
      signature: 'query_sig',
    );
    final queryPayload = jsonEncode(signedQuery);

    app.onData(node, 'mesh_notes', AppMessageType.queryAppType.value, queryPayload);

    // Verify mockOverlay sent the provide payload back
    expect(mockOverlay.sentData.length, 1);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.provideAppType.value);
    expect(mockOverlay.sentData[0]['data'], providePayload);
    expect(mockOverlay.sentData[0]['node'], node);

    // 3. Send publishAppType
    mockOverlay.sentData.clear();
    final node2 = VillagerNode(host: '127.0.0.1', port: 9090);
    node2.nodeId = 'node_2';
    mockOverlay.mockNodes.addAll([node, node2]);

    final broadcast = {
      'messages': {
        'latest_version': 'latest_version_hash_123',
        'latest_version_timestamp': '123456',
      }
    };
    final serverUser = signing.getCompressedPublicKey();
    final signedPublish = SignedMessage(
      userPublicId: serverUser,
      data: jsonEncode(broadcast),
      signature: 'publish_sig',
    );
    final publishPayload = jsonEncode(signedPublish);

    // Send publish from node (node_1)
    app.onData(node, 'mesh_notes', AppMessageType.publishAppType.value, publishPayload);

    expect(dbHelper.getLatestVersion(serverUser, 'latest_version'), 'latest_version_hash_123');
    expect(dbHelper.getLatestVersionTimestamp(serverUser, 'latest_version'), isNotNull);

    // Verify publish is not relayed to node2, and server queries the sender for the version tree instead.
    expect(mockOverlay.sentData.length, 1);
    expect(mockOverlay.sentData[0]['node'], node);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.queryAppType.value);
    final queryAfterPublish = SignedMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
    expect(queryAfterPublish.userPublicId, serverUser);
    expect(VerifyingWrapper.loadKey(queryAfterPublish.userPublicId).ver(HashUtil.hashText(queryAfterPublish.data), queryAfterPublish.signature), isTrue);
    final requiredAfterPublish = RequireVersions.fromJson(jsonDecode(queryAfterPublish.data));
    expect(requiredAfterPublish.requiredVersions, ['version_tree']);

    mockOverlay.sentData.clear();
    dbHelper.saveObject(
      userPublicKey: serverUser,
      key: 'version_tree',
      subKey: '',
      timestamp: 123456,
      data: 'encrypted_tree',
      signature: 'tree_sig',
      envelope: 'tree_env',
    );
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
      envelope: 'cached_env',
    );
    final cachedBroadcast = {
      'messages': {
        'latest_version': 'already_cached_version_hash',
      }
    };
    final cachedPublish = SignedMessage(
      userPublicId: serverUser,
      data: jsonEncode(cachedBroadcast),
      signature: 'publish_sig_cached',
    );
    app.onData(node, 'mesh_notes', AppMessageType.publishAppType.value, jsonEncode(cachedPublish));

    expect(mockOverlay.sentData, isEmpty);

    mockOverlay.sentData.clear();
    final otherUserBroadcast = {
      'messages': {
        'latest_version': 'other_user_version_hash',
      }
    };
    final otherUserPublish = SignedMessage(
      userPublicId: 'other_user',
      data: jsonEncode(otherUserBroadcast),
      signature: 'other_publish_sig',
    );
    app.onData(node, 'mesh_notes', AppMessageType.publishAppType.value, jsonEncode(otherUserPublish));

    expect(dbHelper.getLatestVersion('other_user', 'latest_version'), 'other_user_version_hash');
    expect(mockOverlay.sentData.length, 1);
    expect(mockOverlay.sentData[0]['node'], node);
    expect(mockOverlay.sentData[0]['type'], AppMessageType.queryAppType.value);
    final otherUserQuery = SignedMessage.fromJson(jsonDecode(mockOverlay.sentData[0]['data'] as String));
    expect(otherUserQuery.userPublicId, serverUser);
    expect(VerifyingWrapper.loadKey(otherUserQuery.userPublicId).ver(HashUtil.hashText(otherUserQuery.data), otherUserQuery.signature), isTrue);
    final otherUserRequired = RequireVersions.fromJson(jsonDecode(otherUserQuery.data));
    expect(otherUserRequired.requiredVersions, ['version_tree']);
  });
}
