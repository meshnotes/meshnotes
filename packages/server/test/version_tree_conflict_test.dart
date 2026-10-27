import 'dart:convert';
import 'dart:io';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/application/version_chain_api.dart';
import 'package:libp2p/dal/village_db.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:server/relay_application.dart';
import 'package:server/server_db.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';
import 'server_test.dart' show MockVillageOverlay;

void main() {
  MyLogger.initForConsoleTest(name: 'conflict', debug: false);
  late Directory dir;
  late ServerDbHelper db;
  late RelayApplication app;
  late MockVillageOverlay overlay;
  late SigningWrapper owner;
  late VillagerNode node;
  String signed(String data, SigningWrapper key) => jsonEncode(UncipherMessage(userPublicId: key.getCompressedPublicKey(), data: data, signature: key.sign(HashUtil.hashText(data))));
  String publish(String version) {
    final message = BroadcastMessages(type: versionChainBroadcastType, userPublicId: owner.getCompressedPublicKey(), signature: '',
      messages: {'latest_version': version, 'latest_version_timestamp': '100'});
    message.signature = owner.sign(HashUtil.hashText(message.toSignableString()));
    return ' ${jsonEncode(message)} ';
  }
  void send(String payload, {SigningWrapper? sender}) => app.onData(node, 'mesh_notes', 'publish', signed(payload, sender ?? owner));
  String resolve(String version, String original) => jsonEncode({'type': versionTreeResolveType, resolvedVersionKey: version, 'publish': original});
  String? latest() => db.getLatestVersion(owner.getCompressedPublicKey(), 'latest_version');
  void provideTree(String version, {int timestamp = 100, String? data}) {
    final raw = UnsignedResource(key: resourceKeyVersionTree, subKey: version, timestamp: timestamp, data: data ?? 'tree-$version');
    final resource = CipherMessage.fromRaw(raw, owner.sign(HashUtil.hashText(raw.getFeature())));
    final payload = CipherMessages(userPublicId: owner.getCompressedPublicKey(), resources: [resource], signature: owner.sign(HashUtil.hashText(CipherMessages.getFeature([resource]))));
    app.onData(node, 'mesh_notes', 'provide', jsonEncode(payload));
  }
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('conflict_test');
    db = ServerDbHelper();
    await db.init(dir.path);
    final villageDb = VillageDbHelper();
    await villageDb.init(dir.path);
    overlay = MockVillageOverlay();
    owner = SigningWrapper.random();
    node = VillagerNode(host: '127.0.0.1', port: 12345)..publicKey = owner.getCompressedPublicKey();
    app = RelayApplication(overlay: overlay, db: villageDb, serverDb: db, signing: SigningWrapper.random(), upperAppName: 'mesh_notes', publishIntervalSeconds: 0);
  });
  tearDown(() async => dir.delete(recursive: true));
  test('resolve cannot initialize an empty relay or accept a nested resolve', () {
    final a = publish('a');
    send(resolve('missing', a));
    expect(latest(), isNull);
    expect(db.getLatestPublishPayloads(), isEmpty);
    send(a);
    expect(latest(), isNull);
    provideTree('a');
    expect(latest(), 'a');
    expect(db.getLatestPublishPayloads().single.payload, a);
    send(resolve('a', resolve('a', publish('b'))));
    expect(latest(), 'a');
    expect(db.getLatestPublishPayloads().single.payload, a);
  });
  test('different ordinary publish conflicts without changing raw accepted payload', () {
    final a = publish('a');
    send(a);
    provideTree('a');
    overlay.sentData.clear();
    send(publish('b'));
    expect(latest(), 'a');
    expect(db.getLatestPublishPayloads().single.payload, a);
    final reply = UncipherMessage.fromJson(jsonDecode(overlay.sentData.single['data']));
    expect(jsonDecode(reply.data)['type'], 'version_tree_conflict');
    expect(jsonDecode(reply.data)['conflict_version'], 'a');
    expect(VerifyingWrapper.loadKey(reply.userPublicId).ver(HashUtil.hashText(reply.data), reply.signature), isTrue);
  });
  test('resolve CAS preserves raw signed inner and rejects concurrent stale resolve', () {
    send(publish('a'));
    provideTree('a');
    final b = publish('b');
    send(resolve('a', b));
    expect(latest(), 'a');
    expect(db.getVersionTree(owner.getCompressedPublicKey())!.data, 'tree-a');
    provideTree('b');
    expect(latest(), 'b');
    expect(db.getLatestPublishPayloads().single.payload, b);
    expect(db.getVersionTree(owner.getCompressedPublicKey())!.data, 'tree-b');
    send(resolve('a', publish('c')));
    expect(latest(), 'b');
    final reply = UncipherMessage.fromJson(jsonDecode(overlay.sentData.last['data']));
    expect(jsonDecode(reply.data)['conflict_version'], 'b');
  });
  test('same version repairs missing objects even when cached tree timestamp matches', () {
    send(publish('a'));
    db.saveVersionTree(userPublicKey: owner.getCompressedPublicKey(), resource: CipherMessage(key: resourceKeyVersionTree, subKey: 'a', timestamp: 100, data: 'tree', signature: 'unused'));
    overlay.sentData.clear();
    send(publish('a'));
    expect(overlay.sentData.any((m) => m['type'] == 'offer'), isTrue);
  });
  test('delayed and unapproved trees cannot overwrite approved tree', () {
    void provide(String version) {
      final raw = UnsignedResource(key: resourceKeyVersionTree, subKey: version, timestamp: 100, data: 'tree-$version');
      final resource = CipherMessage.fromRaw(raw, owner.sign(HashUtil.hashText(raw.getFeature())));
      final payload = CipherMessages(userPublicId: owner.getCompressedPublicKey(), resources: [resource], signature: owner.sign(HashUtil.hashText(CipherMessages.getFeature([resource]))));
      app.onData(node, 'mesh_notes', 'provide', jsonEncode(payload));
    }
    send(publish('a'));
    provide('a');
    send(resolve('a', publish('b')));
    provide('b');
    provide('a');
    expect(db.getVersionTree(owner.getCompressedPublicKey())!.data, 'tree-b');
  });
  test('provide and query cannot cross owner boundaries or inject unsigned objects', () {
    send(publish('a'));
    final forged = CipherMessages(userPublicId: owner.getCompressedPublicKey(), resources: [
      CipherMessage(key: 'a', subKey: '', timestamp: 100, data: 'poison', signature: 'invalid'),
    ], signature: 'invalid');
    app.onData(node, 'mesh_notes', 'provide', jsonEncode(forged));
    expect(db.hasObject(owner.getCompressedPublicKey(), 'a'), isFalse);
    // A valid batch signature cannot bless an invalid individual resource signature.
    forged.signature = owner.sign(HashUtil.hashText(CipherMessages.getFeature(forged.resources)));
    app.onData(node, 'mesh_notes', 'provide', jsonEncode(forged));
    expect(db.hasObject(owner.getCompressedPublicKey(), 'a'), isFalse);
    db.saveObject(userPublicKey: owner.getCompressedPublicKey(), key: 'a', subKey: '', timestamp: 1, data: 'secret', signature: 'owner-sign');
    overlay.sentData.clear();
    final other = SigningWrapper.random();
    node.publicKey = other.getCompressedPublicKey();
    app.onData(node, 'mesh_notes', 'query', signed(jsonEncode(RequireVersions(requiredVersions: ['a'])), owner));
    expect(overlay.sentData, isEmpty);
  });
  test('invalid signatures, cross owner and invalid resolve leave accepted state untouched', () {
    send(publish('a'));
    provideTree('a');
    final b = publish('b');
    send(resolve('a', b.replaceFirst('"b"', '"tampered"')));
    expect(latest(), 'a');
    final other = SigningWrapper.random();
    node.publicKey = other.getCompressedPublicKey();
    send(resolve('a', b), sender: other);
    expect(latest(), 'a');
    node.publicKey = owner.getCompressedPublicKey();
    send(jsonEncode({'type': 'version_tree_resolve', 'publish': b}));
    expect(latest(), 'a');
  });
  test('a pending claim keeps the stored tree and ignores another version', () {
    send(publish('a'));
    provideTree('a');
    send(resolve('a', publish('b')));
    overlay.sentData.clear();
    send(resolve('a', publish('c')));
    expect(latest(), 'a');
    expect(db.getPendingClaim(owner.getCompressedPublicKey())!.claimedVersion, 'b');
    expect(db.getVersionTree(owner.getCompressedPublicKey())!.data, 'tree-a');
    expect(overlay.sentData, isEmpty);
  });
  test('a timed out pending claim can be replaced without dropping the stored tree', () {
    send(publish('a'));
    provideTree('a');
    final short = RelayApplication(overlay: overlay, db: VillageDbHelper(), serverDb: db, signing: SigningWrapper.random(), upperAppName: 'mesh_notes', publishIntervalSeconds: 0, pendingTimeoutMs: 0);
    short.onData(node, 'mesh_notes', 'publish', signed(resolve('a', publish('b')), owner));
    expect(db.getPendingClaim(owner.getCompressedPublicKey())!.claimedVersion, 'b');
    short.onData(node, 'mesh_notes', 'publish', signed(resolve('a', publish('c')), owner));
    expect(latest(), 'a');
    expect(db.getPendingClaim(owner.getCompressedPublicKey())!.claimedVersion, 'c');
    expect(db.getVersionTree(owner.getCompressedPublicKey())!.data, 'tree-a');
  });
}
