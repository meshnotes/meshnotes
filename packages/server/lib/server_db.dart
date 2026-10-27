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

class PendingVersionClaim {
  final String userPublicKey;
  final String claimedVersion;
  final int? claimedTimestamp;
  final String payload;
  final String? resolvedVersion;
  final int startedAt;
  final int queryAttempts;

  PendingVersionClaim({
    required this.userPublicKey,
    required this.claimedVersion,
    required this.claimedTimestamp,
    required this.payload,
    required this.resolvedVersion,
    required this.startedAt,
    required this.queryAttempts,
  });
}

class PublishAdmission {
  final String? conflictVersion;
  final bool pending;
  final bool steady;
  final bool busy;

  PublishAdmission._({this.conflictVersion, this.pending = false, this.steady = false, this.busy = false});

  factory PublishAdmission.conflict(String version) => PublishAdmission._(conflictVersion: version);
  factory PublishAdmission.pending() => PublishAdmission._(pending: true);
  factory PublishAdmission.steady() => PublishAdmission._(steady: true);
  factory PublishAdmission.busy() => PublishAdmission._(busy: true);
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
    db.execute('CREATE TABLE IF NOT EXISTS pending_version_claims('
        'user_public_key TEXT PRIMARY KEY, '
        'claimed_version TEXT, '
        'claimed_timestamp INT, '
        'payload TEXT, '
        'resolved_version TEXT, '
        'started_at INT, '
        'query_attempts INT)');
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

  /// Decide whether this publish may be recorded as a pending claim.
  /// The stored head, payload, and version tree stay in place until [tryPromotePendingClaim].
  PublishAdmission tryAdmitPublish(String owner, String version, int? timestamp, String payload, String? resolvedVersion, {required int timeoutMs, required int maxQueries}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = getPendingClaim(owner);
    if(existing != null && _pendingExpired(existing, now, timeoutMs, maxQueries)) {
      _database.execute('DELETE FROM pending_version_claims WHERE user_public_key=?', [owner]);
    }
    _database.execute('BEGIN IMMEDIATE');
    try {
      final pending = getPendingClaim(owner);
      if(pending != null) {
        if(pending.claimedVersion != version || pending.claimedTimestamp != timestamp) {
          _database.execute('ROLLBACK');
          return PublishAdmission.busy();
        }
        _database.execute('ROLLBACK');
        return PublishAdmission.pending();
      }
      final current = getLatestVersion(owner, 'latest_version');
      if((resolvedVersion != null && resolvedVersion != current) || (resolvedVersion == null && current != null && current != version)) {
        _database.execute('ROLLBACK');
        return PublishAdmission.conflict(current ?? ''); // A resolve cannot initialize an empty relay.
      }
      final storedTimestamp = getLatestPublishVersionTimestamp(owner);
      if(current == version && (timestamp == null || storedTimestamp == timestamp)) {
        _database.execute('ROLLBACK');
        return PublishAdmission.steady();
      }
      const sql = 'INSERT INTO pending_version_claims(user_public_key, claimed_version, claimed_timestamp, payload, resolved_version, started_at, query_attempts) VALUES(?, ?, ?, ?, ?, ?, 0)';
      _database.execute(sql, [owner, version, timestamp, payload, resolvedVersion, now]);
      _database.execute('COMMIT');
      return PublishAdmission.pending();
    } catch(e) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Replace the stored head, payload, and version tree when [versionTree] matches the pending claim.
  /// Returns false when the tree belongs to some other version; the stored head is left unchanged.
  bool tryPromotePendingClaim({required String userPublicKey, required CipherMessage versionTree}) {
    _database.execute('BEGIN IMMEDIATE');
    try {
      final pending = getPendingClaim(userPublicKey);
      if(pending == null || pending.claimedVersion != versionTree.subKey || (pending.claimedTimestamp != null && pending.claimedTimestamp != versionTree.timestamp)) {
        _database.execute('ROLLBACK');
        return false;
      }
      final current = getLatestVersion(userPublicKey, 'latest_version');
      if(pending.resolvedVersion != null && pending.resolvedVersion != current) {
        _database.execute('ROLLBACK');
        return false;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final timestamp = pending.claimedTimestamp ?? versionTree.timestamp;
      saveLatestVersion(userPublicKey, 'latest_version', pending.claimedVersion, now);
      saveLatestPublishPayload(userPublicKey, pending.claimedVersion, timestamp, pending.payload, now);
      saveVersionTree(userPublicKey: userPublicKey, resource: versionTree);
      _database.execute('DELETE FROM pending_version_claims WHERE user_public_key=?', [userPublicKey]);
      _database.execute('COMMIT');
      return true;
    } catch(e) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  PendingVersionClaim? getPendingClaim(String userPublicKey) {
    const sql = 'SELECT user_public_key, claimed_version, claimed_timestamp, payload, resolved_version, started_at, query_attempts FROM pending_version_claims WHERE user_public_key=? LIMIT 1';
    final resultSet = _database.select(sql, [userPublicKey]);
    if(resultSet.isEmpty) return null;
    return _pendingFromRow(resultSet.first);
  }

  List<PendingVersionClaim> getPendingClaims() {
    const sql = 'SELECT user_public_key, claimed_version, claimed_timestamp, payload, resolved_version, started_at, query_attempts FROM pending_version_claims';
    return _database.select(sql).map(_pendingFromRow).toList();
  }

  void recordPendingQuery(String userPublicKey) {
    _database.execute('UPDATE pending_version_claims SET query_attempts=query_attempts+1 WHERE user_public_key=?', [userPublicKey]);
  }

  void expirePendingClaims(int now, int timeoutMs, int maxQueries) {
    for(final claim in getPendingClaims()) {
      if(_pendingExpired(claim, now, timeoutMs, maxQueries)) {
        _database.execute('DELETE FROM pending_version_claims WHERE user_public_key=?', [claim.userPublicKey]);
      }
    }
  }

  bool _pendingExpired(PendingVersionClaim pending, int now, int timeoutMs, int maxQueries) {
    return pending.queryAttempts >= maxQueries || now - pending.startedAt >= timeoutMs;
  }

  PendingVersionClaim _pendingFromRow(Row row) {
    return PendingVersionClaim(
      userPublicKey: row['user_public_key'] as String,
      claimedVersion: row['claimed_version'] as String,
      claimedTimestamp: row['claimed_timestamp'] as int?,
      payload: row['payload'] as String,
      resolvedVersion: row['resolved_version'] as String?,
      startedAt: row['started_at'] as int,
      queryAttempts: row['query_attempts'] as int,
    );
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
