import 'package:mesh_note/mindeditor/document/collaborate/merge_manager.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';
import 'package:mesh_note/mindeditor/document/collaborate/diff_manager.dart';

void main() {
  setUp(() {
    MyLogger.initForConsoleTest(name: 'test');
  });

  test('Merge to empty version with no conflict', () {
    int timestamp1 = Util.getTimeStamp();
    var diffOperations1 = _genSimpleDiffOperations('ver1', ['a', 'b', 'c'], timestamp1);
    int timestamp2 = timestamp1 + 1000;
    var diffOperations2 = _genSimpleDiffOperations('ver2', ['d', 'e'], timestamp2);
    var mm = MergeManager(baseVersion: null);
    var result = mm.merge(diffOperations1, diffOperations2);

    expect(result.parentsHash.length, 2);
    expect(result.parentsHash[0], 'ver1');
    expect(result.parentsHash[1], 'ver2');

    var docTable = result.table;
    expect(docTable.length, 5);
    expect(docTable[0].docId, 'd');
    expect(docTable[0].title, 'title_d');
    expect(docTable[0].docHash, 'hash_d');

    expect(docTable[1].docId, 'e');
    expect(docTable[1].title, 'title_e');
    expect(docTable[1].docHash, 'hash_e');

    expect(docTable[2].docId, 'a');
    expect(docTable[2].title, 'title_a');
    expect(docTable[2].docHash, 'hash_a');

    expect(docTable[3].docId, 'b');
    expect(docTable[3].title, 'title_b');
    expect(docTable[3].docHash, 'hash_b');

    expect(docTable[4].docId, 'c');
    expect(docTable[4].title, 'title_c');
    expect(docTable[4].docHash, 'hash_c');
  });

  test('Fast forward merge', () {

  });
}

DiffOperations _genSimpleDiffOperations(String version, List<String> names, int timestamp) {
  List<ContentOperation> operations = [];
  String? lastId;
  for(var item in names) {
    var op = ContentOperation(operation: ContentOperationType.add, targetId: item, title: 'title_$item', data: 'hash_$item', previousId: lastId, timestamp: timestamp);
    operations.add(op);
    lastId = item;
  }
  return DiffOperations(operations: operations, versionHash: version);
}