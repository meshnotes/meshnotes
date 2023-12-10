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
    expect(operations[0].operation, ContentOperationType.add);
    expect(operations[0].targetId, 'c');
    expect(operations[0].parentId, null);
    expect(operations[0].previousId, 'b');
    expect(operations[0].title, 'title_c');
    expect(operations[0].data, 'hash_c');
  });

  test('Generate move operations only', () {
    var baseVersion = _genSimpleVersionContent(['c', 'b', 'a']);
    var targetVersion = _genSimpleVersionContent(['a', 'b', 'c']);
    DiffManager dm = DiffManager();
    var result = dm.findDifferentOperation(targetVersion, baseVersion);
    var operations = result.operations;
    expect(operations.length, 2);
    expect(operations[0].operation, ContentOperationType.move);
    expect(operations[0].targetId, 'a');
    expect(operations[0].parentId, null);
    expect(operations[0].previousId, null);

    expect(operations[1].operation, ContentOperationType.move);
    expect(operations[1].targetId, 'b');
    expect(operations[1].parentId, null);
    expect(operations[1].previousId, 'a');
  });

  test('Generate rename operations only', () {
    var baseVersion = _genSimpleVersionContent(['a', 'b', 'c']);
    var targetVersion = _genSimpleVersionContent(['a', 'b', 'c']);
    targetVersion.table[0].title = 'renamed';
    targetVersion.table[2].title = 'renamed2';
    DiffManager dm = DiffManager();
    var result = dm.findDifferentOperation(targetVersion, baseVersion);
    var operations = result.operations;
    expect(operations.length, 2);
    expect(operations[0].operation, ContentOperationType.rename);
    expect(operations[0].targetId, 'a');
    expect(operations[0].title, 'renamed');

    expect(operations[1].operation, ContentOperationType.rename);
    expect(operations[1].targetId, 'c');
    expect(operations[1].title, 'renamed2');
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
    expect(operations[0].operation, ContentOperationType.modify);
    expect(operations[0].targetId, 'a');
    expect(operations[0].data, 'hash_modified');

    expect(operations[1].operation, ContentOperationType.modify);
    expect(operations[1].targetId, 'b');
    expect(operations[1].data, 'hash_modified1');

    expect(operations[2].operation, ContentOperationType.modify);
    expect(operations[2].targetId, 'c');
    expect(operations[2].data, 'hash_modified2');
  });

  test('Generate del operations only', () {
    var baseVersion = _genSimpleVersionContent(['a', 'b', 'c', 'd']);
    var targetVersion = _genSimpleVersionContent(['a', 'c']);
    DiffManager dm = DiffManager();
    var result = dm.findDifferentOperation(targetVersion, baseVersion);
    var operations = result.operations;
    expect(operations.length, 2);
    expect(operations[0].operation, ContentOperationType.del);
    expect(operations[0].targetId, 'b');

    expect(operations[1].operation, ContentOperationType.del);
    expect(operations[1].targetId, 'd');
  });

  test('Generate mix operations', () {
    var baseVersion = _genSimpleVersionContent(['a', 'b', 'c', 'd', 'e']);
    var targetVersion = _genSimpleVersionContent(['0', 'a', 'd', 'f', 'c', 'e', 'g']);
    targetVersion.table[2].title = 'renamed';
    targetVersion.table[5].docHash = 'new_hash';
    DiffManager dm = DiffManager();
    var result = dm.findDifferentOperation(targetVersion, baseVersion);
    var operations = result.operations;
    expect(operations.length, 7);

    expect(_hasAnOperation(operations, ContentOperation(operation: ContentOperationType.add, targetId: '0', timestamp: 0)), true);
    expect(_hasAnOperation(operations, ContentOperation(operation: ContentOperationType.del, targetId: 'b', timestamp: 0)), true);
    expect(_hasAnOperation(operations, ContentOperation(operation: ContentOperationType.move, targetId: 'd', timestamp: 0)), true);
    expect(_hasAnOperation(operations, ContentOperation(operation: ContentOperationType.rename, targetId: 'd', title: 'renamed', timestamp: 0)), true);
    expect(_hasAnOperation(operations, ContentOperation(operation: ContentOperationType.add, targetId: 'f', timestamp: 0)), true);
    expect(_hasAnOperation(operations, ContentOperation(operation: ContentOperationType.modify, targetId: 'e', data: 'new_hash', timestamp: 0)), true);
    expect(_hasAnOperation(operations, ContentOperation(operation: ContentOperationType.add, targetId: 'g', timestamp: 0)), true);

    expect(_hasAnOperation(operations, ContentOperation(operation: ContentOperationType.rename, targetId: 'd', title: 'renamed2', timestamp: 0)), false);
  });
}

VersionContent _genSimpleVersionContent(List<String> tags) {
  List<VersionContentItem> table = [];
  for(var tag in tags) {
    var item = VersionContentItem(docId: tag, docHash: 'hash_$tag', title: 'title_$tag', updatedAt: 0);
    table.add(item);
  }
  return VersionContent(table: table, timestamp: 0, parentsHash: []);
}

bool _hasAnOperation(List<ContentOperation> operations, ContentOperation targetOp) {
  for(var op in operations) {
    if(op.targetId == targetOp.targetId) {
      if(op.operation == targetOp.operation) {
        if(targetOp.title != null && targetOp.title != op.title) {
          return false;
        }
        if(targetOp.data != null && targetOp.data != op.data) {
          return false;
        }
        return true;
      }
    }
  }
  return false;
}