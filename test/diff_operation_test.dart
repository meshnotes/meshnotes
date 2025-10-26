import 'package:mesh_note/mindeditor/document/collaborate/find_operation_types.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';
import 'package:mesh_note/mindeditor/document/collaborate/diff_manager.dart';

void main() {
  setUp(() {
    MyLogger.initForConsoleTest(name: 'test');
  });

  test('Generate add operations only', () {
    var baseVersion = _genSimpleVersionContent(['a', 'b']);
    var targetVersion = _genSimpleVersionContent(['a', 'b', 'c']);
    DiffManager dm = DiffManager();
    var result = dm.findDifferentOperation(targetVersion, baseVersion);
    var operations = result.operations;
    expect(operations.length, 1);
    expect(operations[0].type, TreeOperationType.add);
    expect(operations[0].id, 'c');
    expect(operations[0].parentId, null);
    expect(operations[0].previousId, 'b');
    expect(operations[0].newData, 'hash_c');
  });

  test('Generate move operations only', () {
    var baseVersion = _genSimpleVersionContent(['c', 'b', 'a']);
    var targetVersion = _genSimpleVersionContent(['a', 'b', 'c']);
    DiffManager dm = DiffManager();
    var result = dm.findDifferentOperation(targetVersion, baseVersion);
    var operations = result.operations;
    expect(operations.length, 2);
    final expectedNodes = [
      {
        'id': 'a',
        'parentId': null,
        'previousId': null,
      }, {
        'id': 'b',
        'parentId': null,
        'previousId': 'a',
      }
    ];
    for(var expectedNode in expectedNodes) {
      expect(
        result.operations.any(
          (operation) => (operation.id == expectedNode['id'])
                          && (operation.type == TreeOperationType.move)
                          && (operation.parentId == expectedNode['parentId'])
                          && (operation.previousId == expectedNode['previousId'])
        ),
        isTrue
      );
    }
  });

  test('Generate modify operations only', () {
    var baseVersion = _genSimpleVersionContent(['a', 'b', 'c']);
    var targetVersion = _genSimpleVersionContent(['a', 'b', 'c']);
    targetVersion.table[0].docHash = 'hash_modified';
    targetVersion.table[1].docHash = 'hash_modified1';
    targetVersion.table[2].docHash = 'hash_modified2';
    DiffManager dm = DiffManager();
    var result = dm.findDifferentOperation(targetVersion, baseVersion);
    var operations = result.operations;
    expect(operations.length, 3);
    expect(operations[0].type, TreeOperationType.modify);
    expect(operations[0].id, 'a');
    expect(operations[0].newData, 'hash_modified');

    expect(operations[1].type, TreeOperationType.modify);
    expect(operations[1].id, 'b');
    expect(operations[1].newData, 'hash_modified1');

    expect(operations[2].type, TreeOperationType.modify);
    expect(operations[2].id, 'c');
    expect(operations[2].newData, 'hash_modified2');
  });

  test('Generate del operations only', () {
    var baseVersion = _genSimpleVersionContent(['a', 'b', 'c', 'd']);
    var targetVersion = _genSimpleVersionContent(['a', 'c']);
    DiffManager dm = DiffManager();
    var result = dm.findDifferentOperation(targetVersion, baseVersion);
    var operations = result.operations;
    expect(operations.length, 2);
    expect(operations[0].type, TreeOperationType.del);
    expect(operations[0].id, 'b');

    expect(operations[1].type, TreeOperationType.del);
    expect(operations[1].id, 'd');
  });

  test('Generate mix operations', () {
    var baseVersion = _genSimpleVersionContent(['a', 'b', 'c', 'd', 'e']);
    var targetVersion = _genSimpleVersionContent(['0', 'a', 'd', 'f', 'c', 'e', 'g']);
    targetVersion.table[5].docHash = 'new_hash';
    DiffManager dm = DiffManager();
    var result = dm.findDifferentOperation(targetVersion, baseVersion);
    var operations = result.operations;
    expect(operations.length, 6);

    expect(_hasAnOperation(operations, TreeOperation(type: TreeOperationType.add, id: '0', timestamp: 0)), true);
    expect(_hasAnOperation(operations, TreeOperation(type: TreeOperationType.del, id: 'b', timestamp: 0)), true);
    expect(_hasAnOperation(operations, TreeOperation(type: TreeOperationType.move, id: 'd', timestamp: 0)), true);
    expect(_hasAnOperation(operations, TreeOperation(type: TreeOperationType.add, id: 'f', timestamp: 0)), true);
    expect(_hasAnOperation(operations, TreeOperation(type: TreeOperationType.modify, id: 'e', newData: 'new_hash', timestamp: 0)), true);
    expect(_hasAnOperation(operations, TreeOperation(type: TreeOperationType.add, id: 'g', timestamp: 0)), true);
  });
}

VersionContent _genSimpleVersionContent(List<String> tags) {
  List<VersionContentItem> table = [];
  for(var tag in tags) {
    var item = VersionContentItem(docId: tag, docHash: 'hash_$tag', updatedAt: 0);
    table.add(item);
  }
  return VersionContent(table: table, timestamp: 0, parentsHash: []);
}

bool _hasAnOperation(List<TreeOperation> operations, TreeOperation targetOp) {
  for(var op in operations) {
    if(op.id == targetOp.id) {
      if(op.type == targetOp.type) {
        if(targetOp.newData != null && targetOp.newData != op.newData) {
          return false;
        }
        return true;
      }
    }
  }
  return false;
}