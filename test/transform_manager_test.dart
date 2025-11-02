import 'package:mesh_note/mindeditor/document/collaborate/document_conflict.dart';
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

    expect(result[0].type, TransformType.add);
    expect(result[0].targetId, 'a');
    expect(result[0].data, 'hash_a');

    expect(result[1].type, TransformType.add);
    expect(result[1].targetId, 'b');
    expect(result[1].data, 'hash_b');

    expect(result[2].type, TransformType.add);
    expect(result[2].targetId, 'c');
    expect(result[2].data, 'hash_c');
  });

  test('Generate move operations', () {
    var doc = _genSimpleDocContent(['b', 'c', 'a']);
    var baseDoc = _genSimpleDocContent(['a', 'b', 'c']);
    var tm = TransformManager(baseContent: baseDoc, createdAt: 0);
    var result = tm.findTransformOperations(doc);
    expect(result.length, 2);

    expect(result[0].type, TransformType.move);
    expect(result[0].targetId, 'b');
    expect(result[0].parentId, null);
    expect(result[0].previousId, null);

    expect(result[1].type, TransformType.move);
    expect(result[1].targetId, 'c');
    expect(result[1].parentId, null);
    expect(result[1].previousId, 'b');
  });

  test('Generate del operations', () {
    var doc = _genSimpleDocContent(['a', 'b', 'd']);
    var baseDoc = _genSimpleDocContent(['a', 'b', 'c', 'd']);
    var tm = TransformManager(baseContent: baseDoc, createdAt: 0);
    var result = tm.findTransformOperations(doc);
    expect(result.length, 1);

    expect(result[0].type, TransformType.del);
    expect(result[0].targetId, 'c');
  });

  test('Generate mixed operations', () {
    var doc = _genSimpleDocContent(['a', 'e', 'd', 'f', 'b', 'g']);
    var baseDoc = _genSimpleDocContent(['a', 'b', 'c', 'd']);
    var tm = TransformManager(baseContent: baseDoc, createdAt: 0);
    var result = tm.findTransformOperations(doc);
    expect(result.length, 5);

    expect(result[0].type, TransformType.add);
    expect(result[0].targetId, 'e');
    expect(result[0].parentId, null);
    expect(result[0].previousId, 'a');
    expect(result[0].data, 'hash_e');

    expect(result[1].type, TransformType.move);
    expect(result[1].targetId, 'd');
    expect(result[1].parentId, null);
    expect(result[1].previousId, 'e');

    expect(result[2].type, TransformType.add);
    expect(result[2].targetId, 'f');
    expect(result[2].parentId, null);
    expect(result[2].previousId, 'd');
    expect(result[2].data, 'hash_f');

    expect(result[3].type, TransformType.del);
    expect(result[3].targetId, 'c');

    expect(result[4].type, TransformType.add);
    expect(result[4].targetId, 'g');
    expect(result[4].parentId, null);
    expect(result[4].previousId, 'b');
    expect(result[4].data, 'hash_g');
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