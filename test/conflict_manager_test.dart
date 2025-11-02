import 'package:mesh_note/mindeditor/document/collaborate/document_conflict.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    MyLogger.initForConsoleTest(name: 'test');
  });

  test('Generate merged document from empty based document', () {
    var baseDoc = _genSimpleDocContent([]);
    var doc1 = _genSimpleDocContent(['a', 'b', 'c']);
    var doc2 = _genSimpleDocContent(['d', 'e']);

    var cm = DocumentConflictManager(baseDoc: baseDoc);
    var (operations, conflicts) = cm.mergeDocumentOperations(doc1, 0, doc2, 1);
    var newDoc = cm.mergeDocument(operations);
    var contents = newDoc.contents;

    expect(conflicts.isEmpty, true);
    expect(contents.length, 5);

    expect(contents[0].blockId, 'd');
    expect(contents[0].blockHash, 'hash_d');

    expect(contents[1].blockId, 'e');
    expect(contents[1].blockHash, 'hash_e');

    expect(contents[2].blockId, 'a');
    expect(contents[2].blockHash, 'hash_a');

    expect(contents[3].blockId, 'b');
    expect(contents[3].blockHash, 'hash_b');

    expect(contents[4].blockId, 'c');
    expect(contents[4].blockHash, 'hash_c');
  });

  test('Generate merged document from pure del operations', () {
    var baseDoc = _genSimpleDocContent(['a', 'b', 'c', 'd', 'e']);
    var doc1 = _genSimpleDocContent(['a', 'b', 'd']); // delete c and e
    var doc2 = _genSimpleDocContent(['b', 'd', 'e']); // delete a and c

    var cm = DocumentConflictManager(baseDoc: baseDoc);
    var (operations, conflicts) = cm.mergeDocumentOperations(doc1, 0, doc2, 1);
    var newDoc = cm.mergeDocument(operations);
    var contents = newDoc.contents;

    expect(conflicts.isEmpty, true);
    expect(contents.length, 2);

    expect(contents[0].blockId, 'b');
    expect(contents[0].blockHash, 'hash_b');

    expect(contents[1].blockId, 'd');
    expect(contents[1].blockHash, 'hash_d');
  });

  test('Generate merged document from pure move operations', () {
    var baseDoc = _genSimpleDocContent(['a', 'b', 'c', 'd']);
    var doc1 = _genSimpleDocContent(['b', 'a', 'c', 'd']);
    var doc2 = _genSimpleDocContent(['a', 'b', 'd', 'c']);

    var cm = DocumentConflictManager(baseDoc: baseDoc);
    var (operations, conflicts) = cm.mergeDocumentOperations(doc1, 0, doc2, 1);
    var newDoc = cm.mergeDocument(operations);
    var contents = newDoc.contents;

    expect(conflicts.isEmpty, true);
    expect(contents.length, 4);

    expect(contents[0].blockId, 'b');
    expect(contents[0].blockHash, 'hash_b');

    expect(contents[1].blockId, 'd');
    expect(contents[1].blockHash, 'hash_d');

    expect(contents[2].blockId, 'a');
    expect(contents[2].blockHash, 'hash_a');

    expect(contents[3].blockId, 'c');
    expect(contents[3].blockHash, 'hash_c');
  });

  test('Generate merged document from pure modify operations', () {
    var baseDoc = _genSimpleDocContent(['a', 'b', 'c']);
    var doc1 = _genSimpleDocContent(['a', 'b', 'c']);
    var doc2 = _genSimpleDocContent(['a', 'b', 'c']);

    doc1.contents[0].blockHash = 'hash_a_1';
    doc1.contents[1].blockHash = 'hash_b_1';
    doc2.contents[1].blockHash = 'hash_b_2';
    doc2.contents[2].blockHash = 'hash_c_2';

    var cm = DocumentConflictManager(baseDoc: baseDoc);
    var (operations, conflicts) = cm.mergeDocumentOperations(doc1, 0, doc2, 1);
    var newDoc = cm.mergeDocument(operations);
    var contents = newDoc.contents;

    expect(conflicts.isEmpty, true);
    expect(contents.length, 3);

    expect(contents[0].blockId, 'a');
    expect(contents[0].blockHash, 'hash_a_1');

    expect(contents[1].blockId, 'b');
    expect(contents[1].blockHash, 'hash_b_2');

    expect(contents[2].blockId, 'c');
    expect(contents[2].blockHash, 'hash_c_2');
  });

  test('Generate merged document from mixed operations', () {
    var baseDoc = _genSimpleDocContent(['a', 'b', 'c', 'd', 'e']);
    var doc1 = _genSimpleDocContent(['b', 'a', 'c', 'e']); // move b, delete d, modify e
    doc1.contents[3].blockHash = 'hash_e_1';
    var doc2 = _genSimpleDocContent(['a', 'e', 'b', 'c', 'd', 'f']); // move e, modify a, add f
    doc2.contents[0].blockHash = 'hash_a_2';

    var cm = DocumentConflictManager(baseDoc: baseDoc);
    var (operations, conflicts) = cm.mergeDocumentOperations(doc1, 0, doc2, 1);
    var newDoc = cm.mergeDocument(operations);
    var contents = newDoc.contents;

    expect(conflicts.isEmpty, true);
    expect(contents.length, 5);

    expect(contents[0].blockId, 'f');
    expect(contents[0].blockHash, 'hash_f');

    expect(contents[1].blockId, 'b');
    expect(contents[1].blockHash, 'hash_b');

    expect(contents[2].blockId, 'a');
    expect(contents[2].blockHash, 'hash_a_2');

    expect(contents[3].blockId, 'e');
    expect(contents[3].blockHash, 'hash_e_1');

    expect(contents[4].blockId, 'c');
    expect(contents[4].blockHash, 'hash_c');
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