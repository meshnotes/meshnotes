import 'dart:convert';
import 'dart:isolate';
import 'package:flutter_test/flutter_test.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/application/version_chain_api.dart';
import 'package:mesh_note/net/command.dart';
import 'package:mesh_note/net/net_controller.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/document/dal/db_helper.dart';
import 'package:mesh_note/mindeditor/document/dal/doc_data_model.dart';
import 'package:mesh_note/mindeditor/document/doc_content.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:mesh_note/mindeditor/setting/setting.dart';
import 'package:my_log/my_log.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('conflict uses current DAG including deprecated ancestors; only fresh conflict resolves after merge', () async {
    MyLogger.initForConsoleTest(name: 'app-conflict');
    final incoming = ReceivePort();
    final outgoing = ReceivePort();
    final commands = <Message>[];
    outgoing.listen((message) { if(message is Message) commands.add(message); });
    final db = sqlite3.openInMemory();
    final controller = Controller();
    addTearDown(() {
      controller.clearSyncingTasks();
      incoming.close();
      outgoing.close();
      db.dispose();
    });
    final network = NetworkController(Isolate.current, incoming);
    controller.dbHelper = DbHelper(database: db);
    controller.network = network;
    controller.initializeDocumentSync();
    void version(String hash, String parents, int timestamp, {int status = ModelConstants.statusAvailable}) {
      db.execute('INSERT INTO versions VALUES (?, ?, ?, ?, ?, ?)', [hash, parents, timestamp, 0, status, 0]);
    }
    void current(String hash, int timestamp) {
      controller.dbHelper.setFlag(Constants.flagNameCurrentVersion, hash);
      controller.dbHelper.setFlag(Constants.flagNameCurrentVersionTimestamp, '$timestamp');
      controller.docManager.getAllFlatDocumentTitlesUnsorted();
    }
    network.start(Setting('/tmp/meshnotes-conflict-unused.conf'), 'test', UserPrivateInfo.makeGuest(timestamp: 1), null);
    incoming.sendPort.send(outgoing.sendPort);
    Future<void> flush() async { await Future<void>.delayed(const Duration(milliseconds: 20)); }
    await flush();
    void conflict(String server, String version) => incoming.sendPort.send(Message(cmd: Command.receiveVersionTreeConflict,
      parameter: UncipherMessage(userPublicId: server, data: jsonEncode(VersionTreeConflict(conflictVersion: version, owner: 'guest')), signature: 'already verified'), stats: TimeCostStatistics()));
    version('a', '', 1, status: ModelConstants.statusDeprecated);
    version('b', 'a', 100);
    current('b', 100);
    network.sendVersionBroadcast('b', 100, TimeCostStatistics());
    await flush();
    final original = (commands.last.parameter as SendBroadcastParameter).message.toJson();
    conflict('server1', 'a');
    await flush();
    final known = commands.last.parameter as SendBroadcastParameter;
    expect(known.resolvedVersion, 'a');
    expect(known.targetPublicKey, 'server1');
    expect(known.message.toJson(), original);
    expect(known.message.messages.containsKey(resolvedVersionKey), isFalse);

    // Advance the head without broadcasting: resolve must use the DAG and publish of the same CURRENT head.
    version('new-local', 'b', 150);
    current('new-local', 150);
    conflict('server1', 'b');
    await flush();
    final latest = commands.last.parameter as SendBroadcastParameter;
    expect(latest.message.messages, {'latest_version': 'new-local', 'latest_version_timestamp': '150'});
    expect(latest.resolvedVersion, 'b');

    // DB versions + objects is insufficient: a cached orphan is not part of the current DAG.
    version('c', '', 100);
    db.execute('INSERT INTO objects VALUES (?, ?, ?, ?, ?)', ['c', '{"doc_table":[],"timestamp":100,"parents":[]}', 100, 0, 0]);
    conflict('server1', 'c');
    await flush();
    expect(commands.last.cmd, Command.sendRequireVersions);
    expect((commands.last.parameter as SendRequireVersionsParameter).versions, [resourceKeyVersionTree]);
    final waitingCount = commands.length;
    conflict('server1', 'c');
    conflict('server2', 'another-orphan');
    await flush();
    expect(commands.length, waitingCount, reason: 'one active tree acquisition, no retained per-relay conflicts');
    controller.receiveVersionTree([VersionNode(versionHash: 'missing', createdAt: 200, parents: [])]);
    await flush();
    final fetchingCount = commands.length;
    conflict('server1', 'c');
    await flush();
    expect(commands.length, fetchingCount, reason: 'object download also suppresses tree requests');
    controller.clearSyncingTasks();

    version('merged', 'new-local,c', 200);
    current('merged', 200);
    network.sendVersionBroadcast('merged', 200, TimeCostStatistics());
    await flush();
    expect((commands.last.parameter as SendBroadcastParameter).resolvedVersion, isNull);
    conflict('server1', 'c');
    await flush();
    final merged = commands.last.parameter as SendBroadcastParameter;
    expect(merged.resolvedVersion, 'c');
    expect(merged.message.messages['latest_version'], 'merged');
    conflict('server2', 'b');
    await flush();
    expect((commands.last.parameter as SendBroadcastParameter).targetPublicKey, 'server2');
    final beforeOrdinary = commands.length;
    network.sendVersionBroadcast('merged', 200, TimeCostStatistics());
    await flush();
    expect(commands.length, beforeOrdinary + 1);
    expect((commands.last.parameter as SendBroadcastParameter).resolvedVersion, isNull);

    // Exercise the real Controller -> MergeTask -> DocumentManager path for a cached unmerged head.
    db.execute('DELETE FROM versions');
    db.execute('DELETE FROM objects');
    final base = VersionContent(table: [], timestamp: 1, parentsHash: []);
    final remote = VersionContent(table: [], timestamp: 2, parentsHash: [base.getHash()]);
    version(base.getHash(), '', 1);
    version(remote.getHash(), base.getHash(), 2);
    for(final content in [base, remote]) {
      db.execute('INSERT INTO objects VALUES (?, ?, ?, ?, ?)', [content.getHash(), jsonEncode(content), content.timestamp, 0, 0]);
    }
    current(base.getHash(), 1);
    conflict('server1', remote.getHash());
    await flush();
    expect(commands.last.cmd, Command.sendRequireVersions);
    controller.receiveVersionTree([
      VersionNode(versionHash: base.getHash(), createdAt: 1, parents: []),
      VersionNode(versionHash: remote.getHash(), createdAt: 2, parents: [base.getHash()]),
    ]);
    expect(controller.docManager.getLatestVersion(), remote.getHash());
    expect(controller.dbHelper.hasSyncingVersion(), isFalse);
    network.sendVersionBroadcast(remote.getHash(), 2, TimeCostStatistics());
    await flush();
    expect((commands.last.parameter as SendBroadcastParameter).resolvedVersion, isNull);
    conflict('server1', remote.getHash());
    await flush();
    expect((commands.last.parameter as SendBroadcastParameter).resolvedVersion, remote.getHash());
  });
}
