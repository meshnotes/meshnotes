// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility that Flutter provides. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:mesh_note/init.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/document/document.dart';
import 'package:mesh_note/mindeditor/document/paragraph_desc.dart';
import 'package:mesh_note/mindeditor/document/text_desc.dart';
import 'package:mesh_note/util/idgen.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_note/util/util.dart';

void main() {
  setUpAll(() => appInit(test: true));
  testDelete1();
  testStyleSetting1();
}

void testDelete1() {
  test('Test splitting TextDesc', () {
    var rawJson = r'[{"text": "test"}]';
    var paragraphDesc = _newDocumentWithJson(rawJson);
    
    paragraphDesc.deleteRange(1, 3);
    expect(paragraphDesc.getPlainText(), 'tt');
    var list = paragraphDesc.getTextsClone();
    expect(list.length, 1);
    expect(list[0].text, 'tt');
  });
}

void testStyleSetting1() {
  test('Test setting style', () {
    var rawJson = r'[{"text": "test"}]';
    var paragraphDesc = _newDocumentWithJson(rawJson);

    paragraphDesc.triggerSelectedTextSpanStyle(1, 3, TextDesc.boldKey);
    expect(paragraphDesc.getPlainText(), 'test');
    var list = paragraphDesc.getTextsClone();
    expect(list.length, 3);
    expect(list[0].text, 't');
    expect(list[0].isBold, false);
    expect(list[1].text, 'es');
    expect(list[1].isBold, true);
    expect(list[2].text, 't');
    expect(list[2].isBold, false);
  });
}

ParagraphDesc _newDocumentWithJson(String json) {
  var result = ParagraphDesc.fromStringList(IdGen.getUid(), 'text', json, Constants.blockListTypeNone, Constants.blockLevelDefault);
  Document(id: IdGen.getUid(), paras: [result], parent: Controller.instance.docManager, time: Util.getTimeStamp());
  return result;
}