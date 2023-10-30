import 'dart:isolate';

import 'package:my_log/my_log.dart';

abstract class IsolateTester {
  bool _func1Done = false;
  bool _func2Done = false;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  bool _running = false;

  Future<void> start(String name1, String name2) async {
    if(_running) return;
    _running = true;

    _func1Done = false;
    _func2Done = false;
    _sendPort = null;
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(
      (SendPort sendPort) {
        var _name2 = '';
        // Exchange communication port
        var receivePort = ReceivePort();
        sendPort.send(receivePort.sendPort);

        // Handle messages from main isolate
        receivePort.listen((data) {
          if(data is String) {
            _name2 = data;
            MyLogger.init(name: _name2);
            MyLogger.info('Starting isolate($_name2)');

            Future(() {
              // func2();

              // MyLogger.info('Isolate($_name2) finished');
            //   sendPort.send('func2_done');
            });
          } else {
            MyLogger.debug('Receive unrecognized message: $data');
          }
        });
      },
      // null,
      _receivePort!.sendPort,
    );

    MyLogger.init(name: name1);
    MyLogger.info('Starting isolate($name1)');
    _receivePort!.listen((data) {
      if(data is SendPort) {
        MyLogger.info('Get SendPort from isolate($name2)');
        _sendPort = data;
        _sendPort!.send(name2);

        Future(() {
          // func1();

          MyLogger.info('Isolate($name1) finished');
          _func1Done = true;
          if(_func2Done) {
            _finishTasks();
          }
        });
      } else if(data == 'func2_done') {
        _func2Done = true;
        if(_func1Done) {
          _finishTasks();
        }
      }
    });
  }

  void stop() {
    if(_stop()) {
      MyLogger.info('Force stop isolates');
    }
  }
  void _finishTasks() {
    if(_stop()) {
      MyLogger.info('Finish isolates');
    }
  }

  bool _stop() {
    if(!_running || _receivePort == null || _isolate == null) return false;

    _receivePort!.close();
    _isolate!.kill();
    _running = false;
    _receivePort = null;
    _isolate = null;
    _sendPort = null;
    _func1Done = false;
    _func2Done = false;
    return true;
  }

  void func1();
  void func2();
}