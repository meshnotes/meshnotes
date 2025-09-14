import 'package:my_log/my_log.dart';
import 'package:sqlite3/sqlite3.dart';


abstract class DbScript {
  int version;
  Map<String, String> createSql;

  DbScript({
    required this.version,
    required this.createSql,
  });

  void initDb(Database db) {
    for(var k in createSql.keys) {
      MyLogger.info('MeshNotesDB: executing db init script: $k');
      var sql = createSql[k];
      if(sql != null && sql.isNotEmpty) {
        MyLogger.debug('sql=$sql');
        db.execute(sql);
      }
    }
  }
  /// Returns true if the upgrade is successful, false otherwise
  bool upgradeDb(Database db);
}

class DbVersion1 extends DbScript {
  static const int ver = 1;
  static Map<String, String> sql = {
    'Create settings': 'CREATE TABLE IF NOT EXISTS settings(name TEXT PRIMARY KEY, value TEXT)',
    'Create objects': 'CREATE TABLE IF NOT EXISTS objects(obj_hash TEXT PRIMARY KEY, data TEXT, updated_at INTEGER, created_from INTEGER, status INTEGER)',
    // 'Create doc_list': 'CREATE TABLE IF NOT EXISTS doc_list(doc_id TEXT PRIMARY KEY, doc_hash TEXT, updated_at INTEGER)',
    'Create documents': 'CREATE TABLE IF NOT EXISTS documents(doc_id TEXT PRIMARY KEY, doc_content TEXT, doc_hash TEXT, is_private INTEGER, updated_at INTEGER)',
    'Create blocks': 'CREATE TABLE IF NOT EXISTS blocks(doc_id TEXT, block_id TEXT, data TEXT, updated_at INTEGER, extra TEXT, CONSTRAINT blocks_pk PRIMARY KEY(doc_id, block_id))',
    'Create versions': 'CREATE TABLE IF NOT EXISTS versions(version_hash TEXT PRIMARY KEY, parents TEXT, created_at INTEGER, created_from INTEGER, status INTEGER, sync_status INTEGER)',
    'Create flags': 'CREATE TABLE IF NOT EXISTS flags(name TEXT PRIMARY KEY, value TEXT)',
    // Temporary tables when syncing
    'Create sync_objects': 'CREATE TABLE IF NOT EXISTS sync_objects(obj_hash TEXT PRIMARY KEY, data TEXT, updated_at INTEGER, created_from INTEGER, status INTEGER)', // No status in tmp table
    'Create sync_versions': 'CREATE TABLE IF NOT EXISTS sync_versions(version_hash TEXT PRIMARY KEY, parents TEXT, created_at INTEGER, created_from INTEGER, status INTEGER)', // No sync_status in tmp table
  };
  DbVersion1(): super(version: ver, createSql: sql);

  @override
  bool upgradeDb(Database db) {
    return true;
  }
}

class DbVersion2 extends DbScript {
  static const int ver = 2;
  static Map<String, String> sql = {
    ...DbVersion1.sql,
    // The only change is the documents table
    'Create documents': 'CREATE TABLE IF NOT EXISTS documents(doc_id TEXT PRIMARY KEY, parent_doc_id TEXT DEFAULT NULL, doc_content TEXT, doc_hash TEXT, is_private INTEGER, updated_at INTEGER)',
  };
  DbVersion2(): super(version: ver, createSql: sql);

  @override
  bool upgradeDb(Database db) {
    MyLogger.info('MeshNotesDB: upgrading documents table');
    db.execute('ALTER TABLE documents ADD COLUMN parent_doc_id TEXT DEFAULT NULL');
    // db.execute('CREATE INDEX IF NOT EXISTS idx_documents_parent ON documents(parent_doc_id)');
    return true;
  }
}
