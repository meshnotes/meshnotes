import 'package:my_log/my_log.dart';
import 'package:path/path.dart';
import 'package:sqlite3/sqlite3.dart';

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
    // db.execute('CREATE TABLE IF NOT EXISTS version_trees('
    //     'user_public_key TEXT PRIMARY KEY, '
    //     'updated_at INT, '
    //     'device_id TEXT, '
    //     'dag TEXT)');

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
        'data TEXT, '
        'signature TEXT, '
        'envelope TEXT, '
        'PRIMARY KEY(user_public_key, key))');

    db.execute('CREATE TABLE IF NOT EXISTS latest_versions('
        'user_public_key TEXT, '
        'key TEXT, '
        'latest_version TEXT, '
        'updated_at INT, '
        'PRIMARY KEY(user_public_key, key))');
  }

  // void saveVersionTree(
  //     String userPublicKey, String deviceId, int updatedAt, String dag) {
  //   const sql =
  //       'INSERT INTO version_trees(user_public_key, updated_at, device_id, dag) VALUES(?, ?, ?, ?) '
  //       'ON CONFLICT(user_public_key) DO UPDATE SET updated_at=excluded.updated_at, device_id=excluded.device_id, dag=excluded.dag';
  //   _database.execute(sql, [userPublicKey, updatedAt, deviceId, dag]);
  // }

  void saveObject({
    required String userPublicKey,
    required String key,
    required String subKey,
    required int timestamp,
    required String data,
    required String signature,
    required String envelope,
  }) {
    if (key == 'version_tree') {
      const sql =
          'INSERT INTO objects(user_public_key, key, sub_key, timestamp, data, signature, envelope) '
          'VALUES(?, ?, ?, ?, ?, ?, ?) ON CONFLICT(user_public_key, key) DO UPDATE SET '
          'sub_key=excluded.sub_key, timestamp=excluded.timestamp, data=excluded.data, '
          'signature=excluded.signature, envelope=excluded.envelope';
      _database.execute(sql,
          [userPublicKey, key, subKey, timestamp, data, signature, envelope]);
    } else {
      const sql =
          'INSERT OR IGNORE INTO objects(user_public_key, key, sub_key, timestamp, data, signature, envelope) '
          'VALUES(?, ?, ?, ?, ?, ?, ?)';
      _database.execute(sql,
          [userPublicKey, key, subKey, timestamp, data, signature, envelope]);
    }
  }

  List<String> getEnvelopes(String userPublicKey, List<String> keys) {
    if (keys.isEmpty) {
      return [];
    }
    final placeholders = List.filled(keys.length, '?').join(', ');
    final sql =
        'SELECT DISTINCT envelope FROM objects WHERE user_public_key = ? AND key IN ($placeholders)';
    final params = [userPublicKey, ...keys];
    final results = _database.select(sql, params);
    final List<String> envelopes = [];
    for (var row in results) {
      final env = row['envelope'] as String?;
      if (env != null && env.isNotEmpty) {
        envelopes.add(env);
      }
    }
    return envelopes;
  }

  void saveLatestVersion(
      String userPublicKey, String key, String latestVersion, int updatedAt) {
    // `updatedAt` is the relay server's local update time for this latest-version cache.
    // The app-side version-tree timestamp is stored only on the `objects` row for `version_tree` after that resource is fetched.
    const sql =
        'INSERT INTO latest_versions(user_public_key, key, latest_version, updated_at) VALUES(?, ?, ?, ?) '
        'ON CONFLICT(user_public_key, key) DO UPDATE SET latest_version=excluded.latest_version, updated_at=excluded.updated_at';
    _database.execute(sql, [userPublicKey, key, latestVersion, updatedAt]);
  }

  String? getLatestVersion(String userPublicKey, String key) {
    const sql =
        'SELECT latest_version FROM latest_versions WHERE user_public_key=? AND key=?';
    final resultSet = _database.select(sql, [userPublicKey, key]);
    if (resultSet.isEmpty) {
      return null;
    }
    return resultSet.first['latest_version'] as String?;
  }

  int? getLatestVersionTimestamp(String userPublicKey, String key) {
    const sql =
        'SELECT updated_at FROM latest_versions WHERE user_public_key=? AND key=?';
    final resultSet = _database.select(sql, [userPublicKey, key]);
    if (resultSet.isEmpty) {
      return null;
    }
    return resultSet.first['updated_at'] as int?;
  }

  int? getObjectTimestamp(String userPublicKey, String key) {
    const sql =
        'SELECT timestamp FROM objects WHERE user_public_key=? AND key=? LIMIT 1';
    final resultSet = _database.select(sql, [userPublicKey, key]);
    if (resultSet.isEmpty) {
      return null;
    }
    return resultSet.first['timestamp'] as int?;
  }

  bool hasObject(String userPublicKey, String key) {
    const sql =
        'SELECT 1 FROM objects WHERE user_public_key=? AND key=? LIMIT 1';
    final resultSet = _database.select(sql, [userPublicKey, key]);
    return resultSet.isNotEmpty;
  }

  void upsertClient(String deviceId, String userPublicKey, String ip, int port,
      int updatedAt) {
    const sql =
        'INSERT INTO connected_clients(device_id, user_public_key, ip, port, updated_at) VALUES(?, ?, ?, ?, ?) '
        'ON CONFLICT(device_id) DO UPDATE SET user_public_key=excluded.user_public_key, ip=excluded.ip, port=excluded.port, updated_at=excluded.updated_at';
    _database.execute(sql, [deviceId, userPublicKey, ip, port, updatedAt]);
  }
}
