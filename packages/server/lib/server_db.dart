import 'dart:convert';

import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/application/version_chain_api.dart';
import 'package:my_log/my_log.dart';
import 'package:path/path.dart';
import 'package:sqlite3/sqlite3.dart';

class LatestPublishRecord {
  final String userPublicKey;
  final String latestVersion;
  final int? latestVersionTimestamp;
  final String payload;

  LatestPublishRecord({
    required this.userPublicKey,
    required this.latestVersion,
    required this.latestVersionTimestamp,
    required this.payload,
  });
}

class ServerDbHelper {
  late Database _database;
  static const dbFileName = 'server_village.db';

  Future<void> init(String directoryPath) async {
    final dbFile = join(directoryPath, dbFileName);
    MyLogger.info('ServerDB: start opening db: $dbFile');
    final db = sqlite3.open(dbFile);
    _database = db;

    _createDbIfNecessary(_database);
    MyLogger.info('ServerDB: finish initializing db');
  }

  void _createDbIfNecessary(Database db) {
    MyLogger.info('ServerDB: creating tables if necessary...');
    db.execute('CREATE TABLE IF NOT EXISTS connected_clients('
        'device_id TEXT PRIMARY KEY, '
        'user_public_key TEXT, '
        'ip TEXT, '
        'port INT, '
        'updated_at INT)');

    db.execute('CREATE TABLE IF NOT EXISTS objects('
        'user_public_key TEXT, '
        'key TEXT, '
        'sub_key TEXT, '
        'timestamp INT, '
        'envelope_data TEXT, '
        'PRIMARY KEY(user_public_key, key))');

    db.execute('CREATE TABLE IF NOT EXISTS version_trees('
        'user_public_key TEXT PRIMARY KEY, '
        'key TEXT, '
        'sub_key TEXT, '
        'timestamp INT, '
        'envelope_data TEXT)');

    db.execute('CREATE TABLE IF NOT EXISTS latest_versions('
        'user_public_key TEXT, '
        'key TEXT, '
        'latest_version TEXT, '
        'updated_at INT, '
        'PRIMARY KEY(user_public_key, key))');

    db.execute('CREATE TABLE IF NOT EXISTS latest_publish_payloads('
        'user_public_key TEXT PRIMARY KEY, '
        'latest_version TEXT, '
        'latest_version_timestamp INT, '
        'payload TEXT, '
        'updated_at INT)');
    _addColumnIfMissing(db, 'latest_publish_payloads', 'latest_version_timestamp', 'INT');
  }

  void _addColumnIfMissing(Database db, String tableName, String columnName, String columnType) {
    final columns = db.select('PRAGMA table_info($tableName)');
    final exists = columns.any((row) => row['name'] == columnName);
    if(!exists) {
      db.execute('ALTER TABLE $tableName ADD COLUMN $columnName $columnType');
    }
  }

  void saveObject({
    required String userPublicKey,
    required String key,
    required String subKey,
    required int timestamp,
    required String data,
    required String signature,
  }) {
    if(key == resourceKeyVersionTree) {
      saveVersionTree(userPublicKey: userPublicKey, resource: CipherMessage(key: key, subKey: subKey, timestamp: timestamp, data: data, signature: signature));
      return;
    }
    if(hasObject(userPublicKey, key)) {
      return;
    }

    final envelopeData = jsonEncode(CipherMessage(key: key, subKey: subKey, timestamp: timestamp, data: data, signature: signature));
    const sql = 'INSERT INTO objects(user_public_key, key, sub_key, timestamp, envelope_data) VALUES(?, ?, ?, ?, ?)';
    _database.execute(sql, [userPublicKey, key, subKey, timestamp, envelopeData]);
  }

  void saveVersionTree({
    required String userPublicKey,
    required CipherMessage resource,
  }) {
    const sql =
        'INSERT INTO version_trees(user_public_key, key, sub_key, timestamp, envelope_data) '
        'VALUES(?, ?, ?, ?, ?) ON CONFLICT(user_public_key) DO UPDATE SET '
        'key=excluded.key, sub_key=excluded.sub_key, timestamp=excluded.timestamp, envelope_data=excluded.envelope_data';
    _database.execute(sql, [userPublicKey, resource.key, resource.subKey, resource.timestamp, jsonEncode(resource)]);
  }

  List<CipherMessage> getObjects(String userPublicKey, List<String> keys) {
    if(keys.isEmpty) {
      return [];
    }
    final placeholders = List.filled(keys.length, '?').join(', ');
    final sql = 'SELECT envelope_data FROM objects WHERE user_public_key = ? AND key IN ($placeholders)';
    final params = [userPublicKey, ...keys];
    final results = _database.select(sql, params);
    return results.map((row) => _cipherMessageFromEnvelopeData(row['envelope_data'] as String)).toList();
  }

  CipherMessage? getObject(String userPublicKey, String key) {
    if(key == resourceKeyVersionTree) {
      return getVersionTree(userPublicKey);
    }
    const sql = 'SELECT envelope_data FROM objects WHERE user_public_key = ? AND key = ? LIMIT 1';
    final results = _database.select(sql, [userPublicKey, key]);
    if(results.isEmpty) {
      return null;
    }
    return _cipherMessageFromEnvelopeData(results.first['envelope_data'] as String);
  }

  CipherMessage? getVersionTree(String userPublicKey) {
    const sql = 'SELECT envelope_data FROM version_trees WHERE user_public_key = ? LIMIT 1';
    final results = _database.select(sql, [userPublicKey]);
    if(results.isEmpty) {
      return null;
    }
    return _cipherMessageFromEnvelopeData(results.first['envelope_data'] as String);
  }

  CipherMessage _cipherMessageFromEnvelopeData(String envelopeData) {
    return CipherMessage.fromJson(jsonDecode(envelopeData) as Map<String, dynamic>);
  }

  void saveLatestVersion(String userPublicKey, String key, String latestVersion, int updatedAt) {
    const sql =
        'INSERT INTO latest_versions(user_public_key, key, latest_version, updated_at) VALUES(?, ?, ?, ?) '
        'ON CONFLICT(user_public_key, key) DO UPDATE SET latest_version=excluded.latest_version, updated_at=excluded.updated_at';
    _database.execute(sql, [userPublicKey, key, latestVersion, updatedAt]);
  }

  String? getLatestVersion(String userPublicKey, String key) {
    const sql = 'SELECT latest_version FROM latest_versions WHERE user_public_key=? AND key=?';
    final resultSet = _database.select(sql, [userPublicKey, key]);
    if(resultSet.isEmpty) {
      return null;
    }
    return resultSet.first['latest_version'] as String?;
  }

  void saveLatestPublishPayload(String userPublicKey, String latestVersion, int? latestVersionTimestamp, String payload, int updatedAt) {
    const sql =
        'INSERT INTO latest_publish_payloads(user_public_key, latest_version, latest_version_timestamp, payload, updated_at) VALUES(?, ?, ?, ?, ?) '
        'ON CONFLICT(user_public_key) DO UPDATE SET latest_version=excluded.latest_version, latest_version_timestamp=excluded.latest_version_timestamp, payload=excluded.payload, updated_at=excluded.updated_at';
    _database.execute(sql, [userPublicKey, latestVersion, latestVersionTimestamp, payload, updatedAt]);
  }

  List<LatestPublishRecord> getLatestPublishPayloads() {
    const sql = 'SELECT user_public_key, latest_version, latest_version_timestamp, payload FROM latest_publish_payloads';
    final resultSet = _database.select(sql);
    return resultSet.map((row) => LatestPublishRecord(
      userPublicKey: row['user_public_key'] as String,
      latestVersion: row['latest_version'] as String,
      latestVersionTimestamp: row['latest_version_timestamp'] as int?,
      payload: row['payload'] as String,
    )).toList();
  }

  int? getLatestPublishVersionTimestamp(String userPublicKey) {
    const sql = 'SELECT latest_version_timestamp FROM latest_publish_payloads WHERE user_public_key=? LIMIT 1';
    final resultSet = _database.select(sql, [userPublicKey]);
    if(resultSet.isEmpty) {
      return null;
    }
    return resultSet.first['latest_version_timestamp'] as int?;
  }

  int? getLatestVersionTimestamp(String userPublicKey, String key) {
    const sql = 'SELECT updated_at FROM latest_versions WHERE user_public_key=? AND key=?';
    final resultSet = _database.select(sql, [userPublicKey, key]);
    if(resultSet.isEmpty) {
      return null;
    }
    return resultSet.first['updated_at'] as int?;
  }

  int? getObjectTimestamp(String userPublicKey, String key) {
    if(key == resourceKeyVersionTree) {
      return getVersionTreeTimestamp(userPublicKey);
    }
    const sql = 'SELECT timestamp FROM objects WHERE user_public_key=? AND key=? LIMIT 1';
    final resultSet = _database.select(sql, [userPublicKey, key]);
    if(resultSet.isEmpty) {
      return null;
    }
    return resultSet.first['timestamp'] as int?;
  }

  int? getVersionTreeTimestamp(String userPublicKey) {
    const sql = 'SELECT timestamp FROM version_trees WHERE user_public_key=? LIMIT 1';
    final resultSet = _database.select(sql, [userPublicKey]);
    if(resultSet.isEmpty) {
      return null;
    }
    return resultSet.first['timestamp'] as int?;
  }

  bool hasObject(String userPublicKey, String key) {
    if(key == resourceKeyVersionTree) {
      return getVersionTree(userPublicKey) != null;
    }
    const sql = 'SELECT 1 FROM objects WHERE user_public_key=? AND key=? LIMIT 1';
    final resultSet = _database.select(sql, [userPublicKey, key]);
    return resultSet.isNotEmpty;
  }

  void upsertClient(String deviceId, String userPublicKey, String ip, int port, int updatedAt) {
    const sql =
        'INSERT INTO connected_clients(device_id, user_public_key, ip, port, updated_at) VALUES(?, ?, ?, ?, ?) '
        'ON CONFLICT(device_id) DO UPDATE SET user_public_key=excluded.user_public_key, ip=excluded.ip, port=excluded.port, updated_at=excluded.updated_at';
    _database.execute(sql, [deviceId, userPublicKey, ip, port, updatedAt]);
  }
}
