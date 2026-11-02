import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/controller/selection_controller.dart';
import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/setting/setting.dart';
import 'package:mesh_note/mindeditor/user/encrypted_user_private_info.dart';
import 'package:mesh_note/net/net_controller.dart';
import 'package:mesh_note/page/doc_navigator.dart';
import 'package:mesh_note/page/sync_progress_widget.dart';
import 'package:mesh_note/tasks/event_tasks.dart';
import 'package:my_log/my_log.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mesh_note/local_state/local_state_store.dart';
import 'package:mesh_note/mindeditor/document/doc_title_node.dart';
import 'package:mesh_note/platform/recent_notes_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  DocTitleMeta note(String id, int timestamp, {String? title}) => DocTitleMeta(docId: id, title: title ?? id, isPrivate: 0, timestamp: timestamp, orderId: 0);

  testWidgets('sync indicator places only the current direction below percentage', (tester) async {
    for(final direction in SyncDirection.values) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SyncProgressWidget(progress: 10, direction: direction))));
      final icon = direction == SyncDirection.upload ? Icons.arrow_upward : Icons.arrow_downward;
      expect(find.text('10%'), findsOneWidget);
      expect(find.byIcon(icon), findsOneWidget);
      expect(find.byIcon(direction == SyncDirection.upload ? Icons.arrow_downward : Icons.arrow_upward), findsNothing);
      expect(tester.getCenter(find.byIcon(icon)).dy, greaterThan(tester.getCenter(find.text('10%')).dy));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('creating a document moves navigator highlight to the opened document', (tester) async {
    MyLogger.initForConsoleTest(name: 'navigator');
    SharedPreferences.setMockInitialValues({});
    final directory = Directory.systemTemp.createTempSync('meshnotes-navigator-');
    final database = sqlite3.openInMemory();
    final incoming = ReceivePort();
    final controller = Controller();
    controller.dbHelper = DbHelper(database: database);
    final timers = <Timer>[];
    runZoned(() => controller.initializeDocumentSync(), zoneSpecification: ZoneSpecification(createPeriodicTimer: (self, parent, zone, duration, callback) {
      final timer = parent.createPeriodicTimer(zone, duration, callback);
      timers.add(timer);
      return timer;
    }));
    controller.localState = await LocalStateStore.create();
    controller.network = NetworkController(Isolate.current, incoming);
    controller.setting = Setting('${directory.path}/setting.conf');
    controller.selectionController = SelectionController(controller);
    addTearDown(() {
      for(final timer in timers) { timer.cancel(); }
      controller.clearSyncingTasks();
      incoming.close();
      database.dispose();
      directory.deleteSync(recursive: true);
    });
    controller.setting.load();
    void expectAccountSettingsHidden() {
      final visibleNames = controller.setting.getSettingsByGroup().expand((group) => group.settings).map((item) => item.name);
      expect(visibleNames, isNot(contains('user_info')));
      expect(visibleNames, isNot(contains('password')));
      expect(visibleNames, contains('server_list'));
    }
    expectAccountSettingsHidden();
    final guest = EncryptedUserPrivateInfo(publicKey: 'guest', userName: 'Guest', privateKey: '', timestamp: 1);
    controller.setUserPrivateInfo(guest, '');
    expectAccountSettingsHidden();
    controller.setUserPrivateInfo(guest, '');
    expectAccountSettingsHidden();
    final reloadedSettings = Setting('${directory.path}/setting.conf')..load();
    expect(reloadedSettings.getSetting('user_info'), guest.toBase64());
    expect(reloadedSettings.getSettingsByGroup().expand((group) => group.settings).map((item) => item.name), isNot(contains('user_info')));
    expect(reloadedSettings.getSettingsByGroup().expand((group) => group.settings).map((item) => item.name), isNot(contains('password')));
    final oldId = controller.docManager.newDocument();
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DocumentNavigator())));
    await tester.tap(find.text('New document'));
    await tester.pump();
    expect(controller.docManager.currentDocId, oldId);
    expect(tester.widgetList<ListTile>(find.byType(ListTile)).where((tile) => tile.selected).length, 1);

    await tester.tap(find.byIcon(Icons.edit_square));
    await tester.pump();
    controller.eventTasksManager.triggerUpdateUploading(42, 10, 100, false);
    await tester.pump();
    expect(find.text('10%'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    controller.eventTasksManager.triggerUpdateSyncing(true, 25);
    await tester.pump();
    expect(find.text('25%'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    controller.eventTasksManager.triggerUpdateSyncing(false, 0);
    controller.eventTasksManager.triggerUpdateUploading(42, 100, 100, true);
    await tester.pump();
    expect(find.byType(SyncProgressWidget), findsNothing);
    final state = tester.state<DocumentNavigatorState>(find.byType(DocumentNavigator));
    final newId = controller.docManager.currentDocId;
    expect(newId, isNot(oldId));
    expect(state.selected, state.docList.indexWhere((doc) => doc.docId == newId));
    expect(tester.widgetList<ListTile>(find.byType(ListTile)).where((tile) => tile.selected).length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    for(final timer in timers) { timer.cancel(); }
  });

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
