import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesh_note/local_state/local_state_store.dart';
import 'package:mesh_note/mindeditor/document/doc_title_node.dart';
import 'package:mesh_note/platform/recent_notes_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DocTitleMeta note(String id, int timestamp, {String? title}) => DocTitleMeta(docId: id, title: title ?? id, isPrivate: 0, timestamp: timestamp, orderId: 0);

  test('widget snapshot prefers recently opened notes, removes deleted IDs and limits to six', () {
    final notes = List.generate(8, (i) => note('$i', i, title: i == 0 ? '  ' : null));
    final result = buildRecentNotesSnapshot(notes, ['deleted', '0', '0', '2']);
    expect(result.map((e) => e['id']), ['0', '2', '7', '6', '5', '4']);
    expect(result.first['title'], 'Untitled note');
    expect(notes.first.docId, '0');
    expect(buildRecentNotesSnapshot([], []), isEmpty);
  });

  test('widget links accept only new and a single document ID', () {
    expect(WidgetNoteAction.parse('meshnotes://widget/new')?.isNew, true);
    const id = 'note /中文?';
    expect(WidgetNoteAction.parse(Uri(scheme: 'meshnotes', host: 'widget', pathSegments: ['open', id]).toString())?.documentId, id);
    for(final link in ['https://widget/new', 'meshnotes://other/new', 'meshnotes://widget/open', 'meshnotes://widget/open/a/b', 'garbage']) {
      expect(WidgetNoteAction.parse(link), isNull);
    }
  });

  test('recently opened IDs persist, deduplicate and remain bounded', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStateStore.create();
    for(var i = 0; i < 24; i++) {
      await store.recordRecentDocument('$i');
    }
    await store.recordRecentDocument('3');
    final restored = await LocalStateStore.create();
    expect(restored.getRecentDocumentIds().first, '3');
    expect(restored.getRecentDocumentIds().length, 20);
    expect(restored.getRecentDocumentIds().where((id) => id == '3').length, 1);
  });

  test('native widget bridge publishes JSON and consumes cold and warm taps once', () async {
    const channel = MethodChannel('xyz.meshnotes/recent_notes');
    final published = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if(call.method == 'takePendingLink') return 'meshnotes://widget/new';
      if(call.method == 'updateNotes') published.add(call.arguments as String);
      return null;
    });
    final actions = <WidgetNoteAction>[];
    final bridge = RecentNotesWidgetBridge();
    await bridge.initialize(actions.add);
    await bridge.update([{'id': 'one', 'title': '真实标题'}]);
    expect(actions.single.isNew, true);
    expect(jsonDecode(published.single), [{'id': 'one', 'title': '真实标题'}]);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('openLink', 'meshnotes://widget/open/one')), (_) {});
    expect(actions.last.documentId, 'one');
    expect(actions.length, 2);
    bridge.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
