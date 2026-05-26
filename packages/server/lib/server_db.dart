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
    db.execute('CREATE TABLE IF NOT EXISTS version_trees('
        'user_public_key TEXT PRIMARY KEY, '
        'updated_at INT, '
        'device_id TEXT, '
        'dag TEXT)');

    db.execute('CREATE TABLE IF NOT EXISTS connected_clients('
        'device_id TEXT PRIMARY KEY, '
        'user_public_key TEXT, '
        'ip TEXT, '
        'port INT, '
        'updated_at INT)');
  }

  void saveVersionTree(String userPublicKey, String deviceId, int updatedAt, String dag) {
    const sql = 'INSERT INTO version_trees(user_public_key, updated_at, device_id, dag) VALUES(?, ?, ?, ?) '
        'ON CONFLICT(user_public_key) DO UPDATE SET updated_at=excluded.updated_at, device_id=excluded.device_id, dag=excluded.dag';
    _database.execute(sql, [userPublicKey, updatedAt, deviceId, dag]);
  }

  void upsertClient(String deviceId, String userPublicKey, String ip, int port, int updatedAt) {
    const sql = 'INSERT INTO connected_clients(device_id, user_public_key, ip, port, updated_at) VALUES(?, ?, ?, ?, ?) '
        'ON CONFLICT(device_id) DO UPDATE SET user_public_key=excluded.user_public_key, ip=excluded.ip, port=excluded.port, updated_at=excluded.updated_at';
    _database.execute(sql, [deviceId, userPublicKey, ip, port, updatedAt]);
  }
}
