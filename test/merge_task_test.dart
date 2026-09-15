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
