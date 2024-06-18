import 'dart:developer';
import 'package:logging/logging.dart';

class MyLogger {
  static Logger? logger;
  static String? prefix;
  static const _defaultLogLevel = Level.INFO;

  static void init({bool usePrint=false, bool debug=false, bool verbose=false, required String name}) {
    logger?.clearListeners();

    prefix = name;
    Logger.root.level = _defaultLogLevel;
    if(debug) {
      Logger.root.level = Level.FINE;
    }
    if(verbose) {
      Logger.root.level = Level.ALL;
    }

    if(usePrint) {
      Logger.root.onRecord.listen((record) {
        print('${record.level.name}: ${record.time}: [$prefix] ${record.message}');
      });
    } else {
      Logger.root.onRecord.listen((record) {
        log('${record.level.name}: ${record.time}: [$prefix] ${record.message}', level: record.level.value);
      });
    }
    logger = Logger(name);
  }

  static void initForTest({bool debug=true, required String name}) {
    init(usePrint: true, debug: debug, name: name);
  }

  static void initForConsoleTest({bool debug=true, required String name}) {
    init(usePrint: true, debug: debug, name: name);
  }

  static void shutdown() {
    logger?.clearListeners();
    logger = null;
  }

  static void verbose(String msg) {
    logger!.finer(msg);
  }

  static void debug(String msg) {
    logger!.fine(msg);
  }

  static void info(String msg) {
    logger!.info(msg);
  }

  static void warn(String msg) {
    logger!.warning(msg);
  }

  static void err(String msg) {
    logger!.severe(msg);
  }

  static void fatal(String msg) {
    logger!.severe(msg);
  }
}