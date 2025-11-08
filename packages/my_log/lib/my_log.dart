import 'package:logger/logger.dart';

class MyLogger {
  static Logger? logger;
  static String? prefix;
  static const _defaultLogLevel = Level.info;
  static String logName = '';
  static bool _isDebug = false;

  static void init({bool usePrint=false, bool debug=false, bool verbose=false, required String name}) {
    if(logger != null) return;

    var loggerLevel = _defaultLogLevel;
    if(debug) {
      loggerLevel = Level.debug;
      _isDebug = true;
    }
    if(verbose) {
      loggerLevel = Level.trace;
      _isDebug = true;
    }

    logName = '[$name]';

    logger ??= Logger(
      printer: SimplePrinter(printTime: true, colors: true),
      level: loggerLevel,
      output: ConsoleOutput(),
      filter: ProductionFilter(),
    );
  }

  static void resetOutputToFile({required String path, bool debug=false, bool verbose=false}) {
    logger?.close();
    var loggerLevel = _defaultLogLevel;
    if(debug) {
      loggerLevel = Level.debug;
    }
    if(verbose) {
      loggerLevel = Level.trace;
    }
    logger = Logger(
      printer: SimplePrinter(printTime: true, colors: false),
      level: loggerLevel,
      output: AdvancedFileOutput.new(
        path: path,
        maxRotatedFilesCount: 10,
      ),
      filter: ProductionFilter(),
    );
  }

  static void initForTest({bool debug=true, required String name}) {
    init(usePrint: true, debug: debug, name: name);
  }

  static void initForConsoleTest({bool debug=true, required String name}) {
    init(usePrint: true, debug: debug, name: name);
  }

  static void shutdown() {
    logger?.close();
    logger = null;
  }

  static void verbose(String msg) {
    logger!.t('$logName: $msg');
  }

  static void debug(String msg) {
    logger!.d('$logName: $msg');
  }

  static void info(String msg) {
    logger!.i('$logName: $msg');
  }

  static void warn(String msg) {
    logger!.w('$logName: $msg');
  }

  static void err(String msg) {
    logger!.e('$logName: $msg');
  }

  static void fatal(String msg) {
    logger!.f('$logName: $msg');
  }

  static bool isDebug() {
    return _isDebug;
  }
}