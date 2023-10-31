import 'dart:ffi';
import 'dart:io';
import 'package:my_log/my_log.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'village_db_script.dart';

class DbUpgradeInfo {
  int targetVersion;
  Function(Database) upgradeFunc;

  DbUpgradeInfo(int ver, Function(Database) func): targetVersion = ver, upgradeFunc = func;
}

class VillageDbHelper {
  late Database _database;
  static const dbFileName = 'village_db.db';
  VillageDbScript dbScript = VillageDbVersion1();
  static final Map<int, DbUpgradeInfo> _upgradeStrategy = {
    1: DbUpgradeInfo(2, VillageDbFake().upgradeDb),
  };

  static DynamicLibrary _openOnLinux() {
    final scriptDir = File(Platform.script.toFilePath()).parent;
    final libraryNextToScript = File('${scriptDir.path}/libsqlite3-dev.so');
    return DynamicLibrary.open(libraryNextToScript.path);
  }
  static DynamicLibrary _openOnWindows() {
    final scriptDir = File(Platform.script.toFilePath()).parent;
    final libraryNextToScript = File('${scriptDir.path}/sqlite3.dll');
    return DynamicLibrary.open(libraryNextToScript.path);
  }

  Future<void> init() async {
    open.overrideFor(OperatingSystem.linux, _openOnLinux);
    open.overrideFor(OperatingSystem.windows, _openOnWindows);
    final directory = await getApplicationDocumentsDirectory();
    final dbFile = join(directory.path, dbFileName);
    MyLogger.debug('VillageDB: start opening db: $dbFile');
    final db = sqlite3.open(dbFile);
    MyLogger.debug('VillageDB: finish loading sqlite3');
    _database = db;

    _upgradeDbIfNecessary(_database);
    _createDbIfNecessary(_database);
    _setVersion(db, dbScript.version);
    MyLogger.info('VillageDB: finish initializing db');
  }

  void _createDbIfNecessary(Database db) {
    MyLogger.info('VillageDB: creating tables if necessary...');
    dbScript.initDb(db);
  }

  static void _setVersion(Database db, int version) async {
    db.select('PRAGMA user_version=$version');
  }
  static int? _getVersion(Database db) {
    const versionKey = 'user_version';
    final result = db.select('PRAGMA $versionKey');
    MyLogger.verbose('VillageDB: PRAGMA user_version=$result');
    for(final row in result) {
      if(row.containsKey(versionKey)) {
        return row[versionKey];
      }
    }
    return null;
  }

  void _upgradeDbIfNecessary(Database db) {
    var version = dbScript.version;
    MyLogger.debug('VillageDB: checking for db upgrade...');
    final oldVersion = _getVersion(db);
    MyLogger.debug('VillageDB: oldVersion=$oldVersion, targetVersion=$version');
    if(oldVersion != null && oldVersion > 0 && oldVersion < version) {
      for(int ver = oldVersion; ver < version;) {
        if(!_upgradeStrategy.containsKey(ver)) {
          ver++;
          continue;
        }
        var info = _upgradeStrategy[ver]!;
        var nextVersion = info.targetVersion;
        MyLogger.info('VillageDB: upgrading from version $ver to version $nextVersion...');
        info.upgradeFunc(db);
        ver = nextVersion;
      }
    }
  }
}