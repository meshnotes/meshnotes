import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/application/version_chain_api.dart';
import 'package:mesh_note/mindeditor/document/collaborate/merge_task.dart';
import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:my_log/my_log.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    MyLogger.initForConsoleTest(name: 'test');
  });

  test('tree acquisition expires without progress; duplicates do not renew it', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    var now = 1000;
    final task = MergeTask(db: DbHelper(database: database), now: () => now, sendRequireVersions: (_) {});
    expect(task.tryBeginVersionTreeRequest(), isTrue);
    now += MergeTask.syncRequestTimeout - 1;
    expect(task.tryBeginVersionTreeRequest(), isFalse);
    now++;
    expect(task.tryBeginVersionTreeRequest(), isTrue);
    task.clearSyncingTasks();
    expect(task.tryBeginVersionTreeRequest(), isTrue);
  });

  test('tree and needed object progress renew suppression but duplicate payloads do not', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    var now = 1000;
    final task = MergeTask(db: DbHelper(database: database), now: () => now, sendRequireVersions: (_) {});
    final tree = [VersionNode(versionHash: 'v', createdAt: 1, parents: [])];
    expect(task.tryBeginVersionTreeRequest(), isTrue);
    now += MergeTask.syncRequestTimeout - 1;
    task.addVersionTree(tree);
    now++;
    expect(task.tryBeginVersionTreeRequest(), isFalse);
    now += MergeTask.syncRequestTimeout - 2;
    task.addResources([UnsignedResource(key: 'v', subKey: '', timestamp: 1,
      data: '{"doc_table":[{"doc_id":"d","doc_hash":"d","updated_at":1}],"timestamp":1,"parents":[]}')]);
    now++;
    expect(task.tryBeginVersionTreeRequest(), isFalse);
    task.addVersionTree(tree);
    now += MergeTask.syncRequestTimeout - 1;
    expect(task.tryBeginVersionTreeRequest(), isTrue);
  });

  test('busy skip retains work and cached orphan can merge on a later tree', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    final db = DbHelper(database: database);
    var now = 1000;
    var busy = true;
    var merged = 0;
    late MergeTask task;
    task = MergeTask(db: db, now: () => now, sendRequireVersions: (_) {}, mergeVersionTree: () {
      expect(task.tryBeginVersionTreeRequest(), isFalse, reason: 'merge is still active');
      if(busy) return false;
      merged++;
      return true;
    });
    final tree = [VersionNode(versionHash: 'cached', createdAt: 1, parents: [])];
    task.tryBeginVersionTreeRequest();
    task.addVersionTree(tree);
    task.addResources([UnsignedResource(key: 'cached', subKey: '', timestamp: 1,
      data: '{"doc_table":[],"timestamp":1,"parents":[]}')]);
    expect(db.hasObject('cached'), isTrue);
    expect(db.getVersionData('cached'), isNotNull);
    expect(db.hasSyncingVersion(), isTrue, reason: 'busy skip is not successful merge');
    expect(task.tryBeginVersionTreeRequest(), isFalse);
    now += MergeTask.syncRequestTimeout;
    expect(task.tryBeginVersionTreeRequest(), isTrue);
    // Also reproduce old cleared sync tables: DB presence must not bypass dependency expansion.
    task.clearSyncingTasks();
    busy = false;
    task.addVersionTree(tree);
    expect(merged, 1);
    expect(db.hasSyncingVersion(), isFalse);
    expect(task.tryBeginVersionTreeRequest(), isTrue);
  });

  test('cached orphan still downloads its missing document before merging', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    final db = DbHelper(database: database);
    database.execute('INSERT INTO versions VALUES (?, ?, ?, ?, ?, ?)', ['cached', '', 1, 0, 0, 0]);
    database.execute('INSERT INTO objects VALUES (?, ?, ?, ?, ?)', ['cached',
      '{"doc_table":[{"doc_id":"d","doc_hash":"d","updated_at":1}],"timestamp":1,"parents":[]}', 1, 0, 0]);
    final requests = <List<String>>[];
    var merges = 0;
    final task = MergeTask(db: db, sendRequireVersions: requests.add, mergeVersionTree: () { merges++; return true; });
    task.addVersionTree([VersionNode(versionHash: 'cached', createdAt: 1, parents: [])]);
    expect(requests, [['d']]);
    expect(merges, 0);
    task.addResources([UnsignedResource(key: 'd', subKey: '', timestamp: 1, data: '{"contents":[]}')]);
    expect(merges, 1);
    expect(task.tryBeginVersionTreeRequest(), isTrue);
  });

  test('existing check retries a busy merge without a new tree or conflict', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    final db = DbHelper(database: database);
    var now = 1000;
    var busy = true;
    var attempts = 0;
    final task = MergeTask(db: db, now: () => now, sendRequireVersions: (_) {}, mergeVersionTree: () { attempts++; return !busy; });
    task.addVersionTree([VersionNode(versionHash: 'v', createdAt: 1, parents: [])]);
    task.addResources([UnsignedResource(key: 'v', subKey: '', timestamp: 1, data: '{"doc_table":[],"timestamp":1,"parents":[]}')]);
    now += 120000;
    task.check();
    expect(attempts, 2);
    now = 1000 + MergeTask.syncRequestTimeout;
    expect(task.tryBeginVersionTreeRequest(), isTrue, reason: 'busy retries do not extend suppression');
    busy = false;
    now += 15000;
    task.check();
    expect(attempts, 3);
    expect(db.hasSyncingVersion(), isFalse);
    expect(task.tryBeginVersionTreeRequest(), isTrue);
  });

  test('failed merge releases request suppression but retains downloaded work', () {
    final database = sqlite3.openInMemory();
    addTearDown(database.dispose);
    final db = DbHelper(database: database);
    final task = MergeTask(db: db, sendRequireVersions: (_) {}, mergeVersionTree: () => throw StateError('merge failed'));
    task.addVersionTree([VersionNode(versionHash: 'v', createdAt: 1, parents: [])]);
    expect(() => task.addResources([UnsignedResource(key: 'v', subKey: '', timestamp: 1,
      data: '{"doc_table":[],"timestamp":1,"parents":[]}')]), throwsStateError);
    expect(db.hasSyncingVersion(), isTrue);
    expect(task.tryBeginVersionTreeRequest(), isTrue);
  });

  test('requests typed missing objects in stages with at most two hashes per round', () {
    final database = sqlite3.openInMemory();
    final db = DbHelper(database: database);
    final requests = <List<String>>[];
    final mergeTask = MergeTask(db: db, sendRequireVersions: (hashes) => requests.add(hashes));
    const versionHash = 'version-hash';
    const timestamp = 123;
    const versionContent = '{"doc_table":[{"doc_id":"doc-1","doc_hash":"doc-1-hash","updated_at":123},{"doc_id":"doc-2","doc_hash":"doc-2-hash","updated_at":123},{"doc_id":"doc-3","doc_hash":"doc-3-hash","updated_at":123}],"timestamp":123,"parents":[]}';
    const doc1Content = '{"contents":[{"block_id":"block-1","block_hash":"block-1-hash","children":[]}]}';
    const doc2Content = '{"contents":[{"block_id":"block-2","block_hash":"block-2-hash","children":[]}]}';

    mergeTask.addVersionTree([VersionNode(versionHash: versionHash, createdAt: timestamp, parents: [])]);
    expect(requests.last, [versionHash]);

    mergeTask.addResources([UnsignedResource(key: versionHash, subKey: '', timestamp: timestamp, data: versionContent)]);
    expect(requests.last, ['doc-1-hash', 'doc-2-hash']);

    mergeTask.addResources([
      UnsignedResource(key: 'doc-1-hash', subKey: '', timestamp: timestamp, data: doc1Content),
      UnsignedResource(key: 'doc-2-hash', subKey: '', timestamp: timestamp, data: doc2Content),
    ]);
    expect(requests.last, ['doc-3-hash', 'block-1-hash']);
    expect(requests.every((request) => request.length <= 2), isTrue);

    mergeTask.addResources([UnsignedResource(key: 'block-1-hash', subKey: '', timestamp: timestamp, data: '{}')]);
    expect(db.hasSyncingObject('block-1-hash'), isTrue);
    expect(requests.last, ['doc-3-hash', 'block-2-hash']);

    database.dispose();
  });
}
