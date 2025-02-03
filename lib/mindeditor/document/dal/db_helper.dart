import 'dart:ffi';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/document/dal/dal_version/db_script.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/open.dart';
import 'package:my_log/my_log.dart';
import '../../../util/idgen.dart';
import 'doc_data_model.dart';

class DbUpgradeInfo {
  int targetVersion;
  Function(Database) upgradeFunc;
  
  DbUpgradeInfo(int ver, Function(Database) func): targetVersion = ver, upgradeFunc = func;
}

class DbHelper {
  late Database _database;
  DbScript dbScript = DbVersion1();
  static const dbFileName = 'mesh_notes.db';
  static final Map<int, DbUpgradeInfo> _upgradeStrategy = {
    1: DbUpgradeInfo(2, DbFake().upgradeDb),
  };

  static DynamicLibrary _openOnLinux() {
    return _tryToLoadLibrary('libsqlite3-dev.so');
  }
  static DynamicLibrary _openOnWindows() {
    return _tryToLoadLibrary('sqlite3.dll');
  }
  static DynamicLibrary _tryToLoadLibrary(String fileName) {
    final List<String> lookupPath = Controller().environment.getLibraryPaths();
    dynamic lastError;
    for(var path in lookupPath) {
      String fullPath = '$path/$fileName';
      try {
        var result = DynamicLibrary.open(fullPath);
        MyLogger.info('Load library($fullPath) success');
        return result;
      } on Error catch(e) {
        MyLogger.warn('Error loading library($fullPath): $e');
        lastError = e;
      }
    }
    throw lastError;
  }

  Future<void> init() async {
    open.overrideFor(OperatingSystem.linux, _openOnLinux);
    open.overrideFor(OperatingSystem.windows, _openOnWindows);
    final dbFile = await Controller().environment.getExistFileFromLibraryPathsByEnvironment(dbFileName);
    MyLogger.info('MeshNotesDB: start opening mesh_notes db: $dbFile');
    final db = sqlite3.open(dbFile);
    MyLogger.debug('MeshNotesDB: finish loading sqlite3');
    _database = db;

    _upgradeDbIfNecessary(_database);
    _createDbIfNecessary(_database);
    _setVersion(db, dbScript.version);
    MyLogger.info('MeshNotesDB: finish initializing db');
  }

  void _createDbIfNecessary(Database db) {
    MyLogger.info('MeshNotesDB: creating tables if necessary...');
    dbScript.initDb(db);
  }

  static void _setVersion(Database db, int version) async {
    db.select('PRAGMA user_version=$version');
  }
  static int? _getDbVersion(Database db) {
    const versionKey = 'user_version';
    final result = db.select('PRAGMA $versionKey');
    MyLogger.verbose('MeshNotesDB: PRAGMA user_version=$result');
    for(final row in result) {
      if(row.containsKey(versionKey)) {
        return row[versionKey];
      }
    }
    return null;
  }

  void _upgradeDbIfNecessary(Database db) {
    var version = dbScript.version;
    MyLogger.debug('MeshNotesDB: checking for db upgrade...');
    final oldVersion = _getDbVersion(db);
    MyLogger.debug('MeshNotesDB: oldVersion=$oldVersion, targetVersion=$version');
    if(oldVersion != null && oldVersion > 0 && oldVersion < version) {
      for(int ver = oldVersion; ver < version;) {
        if(!_upgradeStrategy.containsKey(ver)) {
          ver++;
          continue;
        }
        var info = _upgradeStrategy[ver]!;
        var nextVersion = info.targetVersion;
        MyLogger.info('MeshNotesDB: upgrading from version $ver to version $nextVersion...');
        info.upgradeFunc(db);
        ver = nextVersion;
      }
    }
  }

  Future<void> updateParagraphType(String docId, String id, String type) async {
    const sqlParagraph = 'UPDATE blocks SET type=? WHERE doc_id=? AND id=?';
    _database.execute(sqlParagraph, [type, docId, id]);
  }

  Future<void> updateParagraphListing(String docId, String id, String listing) async {
    const sqlParagraph = 'UPDATE blocks SET listing=? WHERE doc_id=? AND id=?';
    _database.execute(sqlParagraph, [listing, docId, id]);
  }

  Future<void> updateParagraphLevel(String docId, String id, int level) async {
    const sqlParagraph = 'UPDATE blocks SET level=? WHERE doc_id=? AND id=?';
    _database.execute(sqlParagraph, [level, docId, id]);
  }

  void updateDocHash(String docId, String hash, int timestamp) {
    const sql = 'UPDATE documents SET doc_hash=?, updated_at=? WHERE doc_id=?';
    _database.execute(sql, [hash, timestamp, docId]);
  }

  void updateDocContent(String docId, String docContent, int timestamp) {
    const sql = 'UPDATE documents SET doc_content=?, updated_at=? WHERE doc_id=?';
    _database.execute(sql, [docContent, timestamp, docId]);
  }

  void storeDocBlock(String docId, String blockId, String data, int timestamp) {
    const sql = 'INSERT INTO blocks(doc_id, block_id, data, updated_at) VALUES(?, ?, ?, ?) '
        'ON CONFLICT(doc_id, block_id) DO UPDATE SET data=excluded.data, updated_at=excluded.updated_at';
    _database.execute(sql, [docId, blockId, data, timestamp]);
  }

  void updateDocBlockExtra(String docId, String blockId, String extra) {
    const sql = 'UPDATE blocks SET extra=? WHERE doc_id=? AND block_id=?';
    _database.execute(sql, [extra, docId, blockId]);
  }

  void dropDocBlock(String docId, String blockId) {
    const sql = 'DELETE FROM blocks WHERE doc_id=? AND block_id=?';
    _database.execute(sql, [docId, blockId]);
  }

  DocContentDataModel? getDoc(String docId) {
    const sql = 'SELECT doc_content, doc_hash, is_private, updated_at FROM documents WHERE doc_id=?';
    var resultSet = _database.select(sql, [docId]);
    MyLogger.debug('getDoc: result=$resultSet');

    if(resultSet.isEmpty) return null;
    final row = resultSet.first;
    final docContent = row['doc_content'];
    final docHash = row['doc_hash'];
    final isPrivate = row['is_private'];
    final timestamp = row['updated_at'];
    return DocContentDataModel(docId: docId, docContent: docContent, docHash: docHash, isPrivate: isPrivate, timestamp: timestamp);

  }

  Map<String, BlockDataModel> getBlockMapOfDoc(String docId) {
    const sql = 'SELECT block_id, data, updated_at, extra FROM blocks WHERE doc_id=?';
    final resultSet = _database.select(sql, [docId]);
    MyLogger.debug('getBlockMapOfDoc: result=$resultSet');

    var result = <String, BlockDataModel>{};
    for(final row in resultSet) {
      MyLogger.debug('getBlockMapOfDoc: row=$row');
      String blockId = row['block_id'];
      String data = row['data'];
      int updatedAt = row['updated_at'];
      String? extra = row['extra'];
      result[blockId] = BlockDataModel(
        blockId: blockId,
        blockData: data,
        updatedAt: updatedAt,
        blockExtra: extra?? '',
      );
    }
    return result;
  }

  Future<void> updateDoc(String docId, int timestamp) async {
    const sqlUpdateDoc = 'UPDATE docs SET updated_at=? WHERE id=?';
    _database.execute(sqlUpdateDoc, [timestamp, docId]);
  }

  VersionDataModel? getVersionData(String versionHash) {
    const sql = 'SELECT version_hash, parents, created_at, created_from, status, sync_status FROM versions WHERE version_hash=?';
    final resultSet = _database.select(sql, [versionHash]);
    if(resultSet.isEmpty) {
      return null;
    }
    final row = resultSet.first;
    return _packSingleVersionDataModel(row);
  }
  VersionDataModel? getSyncingVersionData(String versionHash) {
    const sql = 'SELECT version_hash, parents, created_at, created_from, status FROM sync_versions WHERE version_hash=?';
    final resultSet = _database.select(sql, [versionHash]);
    if(resultSet.isEmpty) {
      return null;
    }
    final row = resultSet.first;
    return _packSingleVersionDataModel(row);
  }

  List<VersionDataModel> getAllVersions() {
    const sql = 'SELECT version_hash, parents, created_at, created_from, status, sync_status FROM versions';
    final resultSet = _database.select(sql);
    return _packVersionDataModels(resultSet);
  }
  List<VersionDataModel> getAllSyncingVersions() {
    const sql = 'SELECT version_hash, parents, created_at, created_from, status FROM sync_versions';
    final resultSet = _database.select(sql);
    return _packVersionDataModels(resultSet);
  }

  List<String> getAllValidVersionHashes() {
    const sql = 'SELECT version_hash FROM versions';
    final resultSet = _database.select(sql);
    List<String> result = [];
    for(final row in resultSet) {
      String versionHash = row['version_hash'];
      result.add(versionHash);
    }
    return result;
  }

  Map<String, String> getAllTitles() {
    const sql = 'SELECT doc_id, data FROM blocks WHERE block_id=?';
    final resultSet = _database.select(sql, [Constants.keyTitleId]);
    MyLogger.debug('getAllTitles: result=$resultSet');
    var result = <String, String>{};
    for(final row in resultSet) {
      String docId = row['doc_id'];
      String data = row['data'];
      result[docId] = data;
    }
    return result;
  }
  List<DocDataModel> getAllDocuments() {
    const sql = 'SELECT doc_id, doc_hash, updated_at, is_private FROM documents';
    final resultSet = _database.select(sql, []);
    MyLogger.debug('getAllDocuments: result=$resultSet');
    var result = <DocDataModel>[];
    for(final row in resultSet) {
      MyLogger.verbose('getAllDocuments: row=$row');
      String docId = row['doc_id'];
      String docHash = row['doc_hash'];
      int isPrivate = row['is_private'];
      int updatedAt = row['updated_at'];
      result.add(DocDataModel(docId: docId, title: '', hash: docHash, isPrivate: isPrivate, timestamp: updatedAt));
    }
    return result;
  }

  bool hasObject(String hash) {
    const sql = 'SELECT COUNT(*) FROM objects WHERE obj_hash=?';
    final resultSet = _database.select(sql, [hash]);
    if(resultSet.isEmpty) {
      return false;
    }
    final row = resultSet.first;
    int count = row[0];
    return count > 0;
  }
  ObjectDataModel? getObject(String hash) {
    const sql = 'SELECT obj_hash, data, updated_at FROM objects WHERE obj_hash=?';
    final resultSet = _database.select(sql, [hash]);
    return _packObjectDataModel(resultSet);
  }
  void storeObject(String hash, String data, int updatedAt, int createdFrom, int status) {
    //TODO Log an error while conflict
    const sql = 'INSERT INTO objects(obj_hash, data, updated_at, created_from, status) VALUES(?, ?, ?, ?, ?) '
        'ON CONFLICT(obj_hash) DO UPDATE SET '
        '  data=excluded.data,'
        '  updated_at=excluded.updated_at,'
        '  created_from=excluded.created_from,'
        '  status=excluded.status';
    _database.execute(sql, [hash, data, updatedAt, createdFrom, status]);
  }

  bool hasSyncingObject(String hash) {
    const sql = 'SELECT COUNT(*) FROM sync_objects WHERE obj_hash=?';
    final resultSet = _database.select(sql, [hash]);
    if(resultSet.isEmpty) {
      return false;
    }
    final row = resultSet.first;
    int count = row[0];
    return count > 0;
  }
  ObjectDataModel? getSyncingObject(String hash) {
    const sql = 'SELECT obj_hash, data, updated_at FROM sync_objects WHERE obj_hash=?';
    final resultSet = _database.select(sql, [hash]);
    return _packObjectDataModel(resultSet);
  }
  void storeSyncingObject(String hash, String data, int updatedAt, int createdFrom) {
    const sql = 'INSERT INTO sync_objects(obj_hash, data, updated_at, created_from) VALUES(?, ?, ?, ?)';
    _database.execute(sql, [hash, data, updatedAt, createdFrom]);
  }
  bool hasSyncingVersion() {
    const sql = 'SELECT COUNT(*) FROM sync_versions';
    final resultSet = _database.select(sql);
    if(resultSet.isEmpty) {
      return false;
    }
    final row = resultSet.first;
    int count = row[0];
    return count > 0;
  }

  void storeVersion(String hash, String parents, int timestamp, int createdFrom, int status) {
    //TODO Log an error while conflict
    const sql = 'INSERT INTO versions(version_hash, parents, created_at, created_from, status) VALUES(?, ?, ?, ?, ?)';
    _database.execute(sql, [hash, parents, timestamp, createdFrom, status]);
  }
  void storeSyncingVersion(String hash, String parents, int timestamp, int createdFrom, int status) {
    const sql = 'INSERT OR IGNORE INTO sync_versions(version_hash, parents, created_at, created_from, status) VALUES(?, ?, ?, ?, ?)';
    _database.execute(sql, [hash, parents, timestamp, createdFrom, status]);
  }

  void updateVersionStatus(String hash, int status) {
    const sql = 'UPDATE versions SET status=? WHERE version_hash=?';
    _database.execute(sql, [status, hash]);
  }
  void updateVersionSyncStatus(String hash, int syncStatus) {
    const sql = 'UPDATE versions SET sync_status=? WHERE version_hash=?';
    _database.execute(sql, [syncStatus, hash]);
  }

  void updateSyncingVersionStatus(String hash, int status) {
    const sql = 'UPDATE sync_versions SET status=? WHERE version_hash=?';
    _database.execute(sql, [status, hash]);
  }

  void storeFromSyncingTables() {
    const sqlVersions = 'INSERT OR REPLACE INTO versions(version_hash, parents, created_at, created_from, status) '
        'SELECT version_hash, parents, created_at, created_from, status FROM sync_versions';
    _database.execute(sqlVersions);

    const sqlObjects = 'INSERT OR REPLACE INTO objects(obj_hash, data, updated_at, created_from, status) '
        'SELECT obj_hash, data, updated_at, created_from, ${ModelConstants.statusAvailable} FROM sync_objects';
    _database.execute(sqlObjects);
  }

  void clearSyncingTables() {
    const sqlVersions = 'DELETE FROM sync_versions';
    _database.execute(sqlVersions);

    const sqlObjects = 'DELETE FROM sync_objects';
    _database.execute(sqlObjects);
  }

  String? getFlag(String name) {
    const sql = 'SELECT value FROM flags WHERE name=?';
    final resultSet = _database.select(sql, [name]);
    if(resultSet.isEmpty) {
      return null;
    }
    return resultSet.first['value'];
  }
  void setFlag(String name, String value) {
    const sql = 'INSERT INTO flags(name, value) VALUES(?, ?) ON CONFLICT(name) DO UPDATE SET value=excluded.value';
    _database.execute(sql, [name, value]);
  }

  String newDocument(int timestamp) {
    var docId = IdGen.getUid();
    const sql = 'INSERT INTO documents(doc_id, doc_hash, doc_content, is_private, updated_at) VALUES(?, ?, ?, ?, ?)';
    _database.execute(sql, [docId, '', '', ModelConstants.isPrivateNo, timestamp]);

    return docId;
  }

  void deleteDocument(String docId) {
    // Remove from blocks
    const sqlBlocks = 'DELETE FROM blocks WHERE doc_id=?';
    _database.execute(sqlBlocks, [docId]);

    // Remove from doc contents
    const sqlContents = 'DELETE FROM documents WHERE doc_id=?';
    _database.execute(sqlContents, [docId]);
  }

  void insertOrUpdateDoc(String docId, String docHash, int timestamp) {
    // When insert, set doc_content to empty string, is_private to 0. But when update, don't set doc_content and is_private
    const sql = 'INSERT INTO documents(doc_id, doc_hash, doc_content, is_private, updated_at) VALUES(?, ?, ?, ?, ?) '
        'ON CONFLICT(doc_id) DO UPDATE SET doc_hash=excluded.doc_hash, updated_at=excluded.updated_at';
    _database.execute(sql, [docId, docHash, '', ModelConstants.isPrivateNo, timestamp]);
  }

  List<(String, String)> getAllBlocks() {
    const sql = 'SELECT doc_id, block_id FROM blocks WHERE data!=""';
    final resultSet = _database.select(sql);
    MyLogger.debug('getAllBlocks: result=$resultSet');
    if(resultSet.isEmpty) {
      MyLogger.warn('Blocks not found!');
      return [];
    }
    var result = <(String, String)>[];
    for(final row in resultSet) {
      var docId = row['doc_id'];
      var blockId = row['block_id'];
      result.add((docId, blockId));
    }
    return result;
  }
  BlockDataModel? getRawBlockById(String docId, String blockId) {
    const sql = 'SELECT data FROM blocks, updated_at, extra, created_from, status WHERE doc_id=? AND block_id=?';
    final resultSet = _database.select(sql, [docId, blockId]);
    MyLogger.debug('getRawBlockById result=$resultSet');
    if(resultSet.length != 1) {
      MyLogger.warn('Block(doc_id=$docId, block_id=$blockId) not unique!');
      return null;
    }
    final row = resultSet.first;
    String data = row['data'];
    int updatedAt = row['updated_at'];
    String? extra = row['extra'];
    return BlockDataModel(
      blockId: blockId,
      blockData: data,
      updatedAt: updatedAt,
      blockExtra: extra?? '',
    );
  }

  Map<String, String> getSettings() {
    const sql = 'SELECT name, value FROM settings';
    final resultSet = _database.select(sql);
    MyLogger.debug('getSettings result=$resultSet');
    var result = <String, String>{};
    for(final row in resultSet) {
      String name = row['name'];
      String value = row['value'];
      if(name.isEmpty) continue;
      result[name] = value;
    }
    return result;
  }
  bool saveSettings(Map<String, String> settings) {
    String sql = 'INSERT INTO settings(name, value) VALUES';
    var values = <Object>[];
    for(final item in settings.entries) {
      String newLine = '(?, ?),';
      sql += newLine;
      values.add(item.key);
      values.add(item.value);
    }
    sql = sql.substring(0, sql.length - 1) + ' ON CONFLICT(name) DO UPDATE SET value=excluded.value';
    MyLogger.debug('saveSettings: execute sql: "$sql" with values: $values');
    _database.execute(sql, values);
    return false;
  }
  
  List<VersionDataModel> _packVersionDataModels(ResultSet resultSet) {
    List<VersionDataModel> result = [];
    for(final row in resultSet) {
      MyLogger.verbose('getAllVersions: row=$row');
      result.add(_packSingleVersionDataModel(row));
    }
    return result;
  }
  VersionDataModel _packSingleVersionDataModel(Row row) {
    String versionHash = row['version_hash'];
    String parents = row['parents'];
    int timestamp = row['created_at'];
    int? createdFrom = row['created_from'];
    int? dataStatus = row['status'];
    int? syncStatus = row['sync_status'];
    return VersionDataModel(
      versionHash: versionHash,
      parents: parents,
      createdAt: timestamp,
      createdFrom: createdFrom?? Constants.createdFromPeer,
      status: dataStatus?? ModelConstants.statusWaiting,
      syncStatus: syncStatus?? Constants.syncStatusNew,
    );
  }

  ObjectDataModel? _packObjectDataModel(ResultSet resultSet) {
    if(resultSet.isEmpty) {
      return null;
    }
    final row = resultSet.first;
    var key = row['obj_hash'];
    var data = row['data'];
    var timestamp = row['updated_at'];
    var createdFrom = row['created_from'];
    var dataStatus = row['status'];
    return ObjectDataModel(
      key: key,
      data: data,
      timestamp: timestamp,
      createdFrom: createdFrom?? Constants.createdFromPeer,
      status: dataStatus?? ModelConstants.statusWaiting,
    );
  }
}
