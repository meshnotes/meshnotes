import 'package:mesh_note/mindeditor/document/collaborate/find_operation_types.dart';
import 'package:mesh_note/mindeditor/document/collaborate/merge_manager.dart';
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
    var (operations, conflicts) = mm.mergeOperations(diffOperations1, diffOperations2);

    expect(conflicts.length, 0);
    expect(operations.length, 5);

    expect(operations[0].type, TreeOperationType.add);
    expect(operations[0].id, 'a');

    expect(operations[1].type, TreeOperationType.add);
    expect(operations[1].id, 'b');

    expect(operations[2].type, TreeOperationType.add);
    expect(operations[2].id, 'c');

    expect(operations[3].type, TreeOperationType.add);
    expect(operations[3].id, 'd');

    expect(operations[4].type, TreeOperationType.add);
    expect(operations[4].id, 'e');
  });

  test('Fast forward merge', () {

  });
}

DiffOperations _genSimpleDiffOperations(String version, List<String> names, int timestamp) {
  List<TreeOperation> operations = [];
  String? lastId;
  for(var item in names) {
    var op = TreeOperation(type: TreeOperationType.add, id: item, newData: 'hash_$item', previousId: lastId, timestamp: timestamp);
    operations.add(op);
    lastId = item;
  }
  return DiffOperations(operations: operations, versionHash: version);
}