import 'package:mesh_note/mindeditor/document/collaborate/document_conflict.dart';
import 'package:mesh_note/mindeditor/document/collaborate/find_operation_types.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    MyLogger.initForConsoleTest(name: 'test');
  });

  test('Generate transform operations from empty document', () {
    var doc = _genSimpleDocContent(['a', 'b', 'c']);
    var baseDoc = _genSimpleDocContent([]);
    var tm = TransformManager(baseContent: baseDoc, createdAt: 0);
    var result = tm.findTransformOperations(doc);
    expect(result.length, 3);

    expect(result[0].type, TreeOperationType.add);
    expect(result[0].id, 'a');
    expect(result[0].newData, 'hash_a');

    expect(result[1].type, TreeOperationType.add);
    expect(result[1].id, 'b');
    expect(result[1].newData, 'hash_b');

    expect(result[2].type, TreeOperationType.add);
    expect(result[2].id, 'c');
    expect(result[2].newData, 'hash_c');
  });

  test('Generate move operations', () {
    var doc = _genSimpleDocContent(['b', 'c', 'a']);
    var baseDoc = _genSimpleDocContent(['a', 'b', 'c']);
    var tm = TransformManager(baseContent: baseDoc, createdAt: 0);
    var result = tm.findTransformOperations(doc);
    expect(result.length, 1);

    expect(result[0].type, TreeOperationType.move);
    expect(result[0].id, 'a');
    expect(result[0].parentId, null);
    expect(result[0].previousId, 'c');
  });

  test('Generate del operations', () {
    var doc = _genSimpleDocContent(['a', 'b', 'd']);
    var baseDoc = _genSimpleDocContent(['a', 'b', 'c', 'd']);
    var tm = TransformManager(baseContent: baseDoc, createdAt: 0);
    var result = tm.findTransformOperations(doc);
    expect(result.length, 1);

    expect(result[0].type, TreeOperationType.del);
    expect(result[0].id, 'c');
  });

  test('Generate mixed operations', () {
    var doc = _genSimpleDocContent(['a', 'e', 'd', 'f', 'b', 'g']);
    var baseDoc = _genSimpleDocContent(['a', 'b', 'c', 'd']);
    var tm = TransformManager(baseContent: baseDoc, createdAt: 0);
    var result = tm.findTransformOperations(doc);
    expect(result.length, 5);

    final expectedOperations = [
      {
        'type': TreeOperationType.add,
        'id': 'e',
        'parentId': null,
        'previousId': 'a',
        'newData': 'hash_e',
      },
      {
        'type': TreeOperationType.move,
        'id': 'd',
        'parentId': null,
        'previousId': 'e',
      },
      {
        'type': TreeOperationType.add,
        'id': 'f',
        'parentId': null,
        'previousId': 'd',
        'newData': 'hash_f',
      },
      {
        'type': TreeOperationType.del,
        'id': 'c',
        'parentId': null,
        'previousId': null,
        'newData': null,
      },
    ];
    for(var expectedOperation in expectedOperations) {
      expect(result.any((operation) => operation.type == expectedOperation['type'] && operation.id == expectedOperation['id'] && operation.parentId == expectedOperation['parentId'] && operation.previousId == expectedOperation['previousId'] && operation.newData == expectedOperation['newData']), isTrue);
    }
  });

  test('Generate mixed operations with children', () {
    var doc = _genDocContentWithChildren([['a', 'a1'], ['e', 'e1', 'e2'], ['d', 'd1', 'b2', 'd2'], ['c', 'c1'], ['f'], ['c2']]);
    var baseDoc = _genDocContentWithChildren([['a'], ['b', 'b1', 'b2'], ['c', 'c1', 'c2'], ['d', 'd1', 'd2']]);
    var tm = TransformManager(baseContent: baseDoc, createdAt: 0);
    var result = tm.findTransformOperations(doc);
    expect(result.length, 11);

    final expectedOperations = [
      {
        'type': TreeOperationType.add,
        'id': 'a1',
        'parentId': 'a',
        'previousId': null,
        'newData': 'hash_a1',
      },
      {
        'type': TreeOperationType.add,
        'id': 'e',
        'parentId': null,
        'previousId': 'a',
        'newData': 'hash_e',
      },
      {
        'type': TreeOperationType.add,
        'id': 'e1',
        'parentId': 'e',
        'previousId': null,
        'newData': 'hash_e1',
      },
      {
        'type': TreeOperationType.add,
        'id': 'e2',
        'parentId': 'e',
        'previousId': 'e1',
        'newData': 'hash_e2',
      },
      {
        'type': TreeOperationType.move,
        'id': 'd',
        'parentId': null,
        'previousId': 'e',
      },
      // {
      //   'type': TreeOperationType.move,
      //   'id': 'd1',
      //   'parentId': 'd',
      //   'previousId': null,
      // },
      {
        'type': TreeOperationType.move,
        'id': 'b2',
        'parentId': 'd',
        'previousId': 'd1',
      },
      {
        'type': TreeOperationType.move,
        'id': 'd2',
        'parentId': 'd',
        'previousId': 'b2',
      },
      {
        'type': TreeOperationType.add,
        'id': 'f',
        'parentId': null,
        'previousId': 'c',
        'newData': 'hash_f',
      },
      {
        'type': TreeOperationType.move,
        'id': 'c2',
        'parentId': null,
        'previousId': 'f',
      },
      {
        'type': TreeOperationType.del,
        'id': 'b',
      },
      {
        'type': TreeOperationType.del,
        'id': 'b1',
      },
    ];
    for(var expectedOperation in expectedOperations) {
      expect(result.any((operation) => operation.type == expectedOperation['type'] && operation.id == expectedOperation['id'] && operation.parentId == expectedOperation['parentId'] && operation.previousId == expectedOperation['previousId'] && operation.newData == expectedOperation['newData']), isTrue);
    }
  });
}

DocContent _genSimpleDocContent(List<String> raw) {
  var contents = <DocContentItem>[];
  for(var item in raw) {
    var block = DocContentItem(blockId: item, blockHash: 'hash_$item');
    contents.add(block);
  }
  return DocContent(contents: contents);
}

DocContent _genDocContentWithChildren(List<List<String>> raw) {
  var contents = <DocContentItem>[];
  for(var item in raw) {
    var block = DocContentItem(blockId: item[0], blockHash: 'hash_${item[0]}');
    contents.add(block);
    for(var child in item.sublist(1)) {
      var childBlock = DocContentItem(blockId: child, blockHash: 'hash_$child');
      block.children.add(childBlock);
    }
  }
  return DocContent(contents: contents);
}