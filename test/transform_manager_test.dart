import 'package:mesh_note/mindeditor/document/collaborate/conflict_manager.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';
import 'package:mesh_note/mindeditor/document/collaborate/diff_manager.dart';

void main() {
  setUp(() {
    MyLogger.initForConsoleTest(name: 'test');
  });

  test('Generate transform operations from empty document', () {
    var doc = _genSimpleDocContent(['a', 'b', 'c']);
    var baseDoc = _genSimpleDocContent([]);
    var tm = TransformManager();
    var result = tm.findTransformOperations(doc, baseDoc);
    expect(result.length, 3);

    expect(result[0].type, TransformType.add);
    expect(result[0].targetId, 'a');

    expect(result[1].type, TransformType.add);
    expect(result[1].targetId, 'b');

    expect(result[2].type, TransformType.add);
    expect(result[2].targetId, 'c');
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