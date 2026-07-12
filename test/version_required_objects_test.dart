import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/document/dal/doc_data_model.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:mesh_note/net/version_chain_api.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:my_log/my_log.dart';

void main() {
  setUpAll(() {
    MyLogger.initForConsoleTest(name: 'test');
  });

  test('stores required object manifest as one text list per version', () {
    final database = sqlite3.openInMemory();
    final db = DbHelper(database: database);
    const versionHash = 'version-hash';
    const docHash = 'doc-hash';
    const blockHash = 'block-hash';
    const timestamp = 123;
    const docContent = '{"contents":[{"block_id":"block-1","block_hash":"block-hash","children":[]}]}';
    const blockContent = '{"type":"normal","listing":"none","level":0,"text":[]}';
    const versionContent = '{"doc_table":[{"doc_id":"doc-1","doc_hash":"doc-hash","updated_at":123}],"timestamp":123,"parents":[]}';

    db.storeObject(docHash, docContent, timestamp, Constants.createdFromLocal, ModelConstants.statusAvailable);
    db.storeObject(blockHash, blockContent, timestamp, Constants.createdFromLocal, ModelConstants.statusAvailable);
    db.storeObject(versionHash, versionContent, timestamp, Constants.createdFromLocal, ModelConstants.statusAvailable);
    db.storeVersion(versionHash, '', timestamp, Constants.createdFromLocal, ModelConstants.statusAvailable);

    expect(db.getVersionRequiredObjects(versionHash), isEmpty);

    db.storeVersionRequiredObjects(versionHash, {
      docHash: RelatedObject(objHash: docHash, objContent: docContent, createdAt: timestamp),
      blockHash: RelatedObject(objHash: blockHash, objContent: blockContent, createdAt: timestamp),
    });

    expect(db.hasVersionRequiredObjects(versionHash), isTrue);

    final requiredObjects = db.getVersionRequiredObjects(versionHash);
    expect(requiredObjects.keys.toSet(), {docHash, blockHash});
    expect(requiredObjects[docHash]!.objContent, docContent);
    expect(requiredObjects[blockHash]!.objContent, blockContent);

    final rows = database.select('SELECT version_hash, obj_hashes FROM version_required_objects WHERE version_hash=?', [versionHash]);
    expect(rows.length, 1);
    expect(rows.first['obj_hashes'], '["block-hash","doc-hash"]');

    database.dispose();
  });
}
