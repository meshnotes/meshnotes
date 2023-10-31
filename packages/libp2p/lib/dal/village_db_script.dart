import 'package:my_log/my_log.dart';
import 'package:sqlite3/sqlite3.dart';


abstract class VillageDbScript {
  int version;
  Map<String, String> createSql;

  VillageDbScript({
    required this.version,
    required this.createSql,
  });

  void initDb(Database db) {
    for(var k in createSql.keys) {
      MyLogger.info('VillageDB: executing db init script: $k');
      var sql = createSql[k];
      if(sql != null && sql.isNotEmpty) {
        MyLogger.debug('sql=$sql');
        db.execute(sql);
      }
    }
  }
  void upgradeDb(Database db) {}
}

class VillageDbVersion1 extends VillageDbScript {
  static int ver = 1;
  static Map<String, String> sql = {
    'Create objects': 'CREATE TABLE IF NOT EXISTS objects(obj_hash TEXT PRIMARY KEY, data TEXT)',
    'Create versions': 'CREATE TABLE IF NOT EXISTS versions(version_hash TEXT PRIMARY KEY, parents TEXT, created_at INTEGER)',
  };
  VillageDbVersion1(): super(version: ver, createSql: sql);
}

class VillageDbFake extends VillageDbScript {
  static int ver = 2;
  static Map<String, String> sql = {};
  VillageDbFake(): super(version: ver, createSql: sql);

  @override
  void upgradeDb(Database db) {}
}