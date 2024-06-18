import 'dart:async';
import 'dart:isolate';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';

void main() async {
  test('Add application', () async {
    final runner = IsolateTester();
    await runner.start('runner1', 'runner2');
  });
}

class IsolateTester {
  Isolate? _isolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  bool _running = false;

  Future<void> start(String name1, String name2) async {
    if(_running) return;
    _running = true;

    _sendPort = null;
    _receivePort = ReceivePort();
    var completer1 = Completer<bool>();
    var completer2 = Completer<bool>();
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
            MyLogger.initForConsoleTest(name: _name2);
            MyLogger.info('Starting isolate($_name2)');

            Future(() async {
              await func2();

              MyLogger.info('Isolate($_name2) finished');
              sendPort.send('func2_done');
            });
          } else {
            MyLogger.debug('Receive unrecognized message: $data');
          }
        });
      },
      // null,
      _receivePort!.sendPort,
    );

    _receivePort!.listen((data) {
      if(data is SendPort) {
        MyLogger.initForConsoleTest(name: name1);
        MyLogger.info('Get SendPort from isolate($name2)');
        MyLogger.info('Starting isolate($name1)');
        _sendPort = data;
        _sendPort!.send(name2);

        Future(() async {
          await func1();
          await Future.delayed(Duration(seconds: 5));

          MyLogger.info('Isolate($name1) finished');
          completer1.complete(true);
        });
      } else if(data == 'func2_done') {
        completer2.complete(true);
      }
    });
    await completer1.future;
    await completer2.future;
  }

  void stop() {
    if(_stop()) {
      MyLogger.info('Force stop isolates');
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
    return true;
  }

  static int port1 = 1234;
  static int port2 = 8888;
  static Future<void> func1() async {
    bool first = true;
    var overlay = VillageOverlay(
      userInfo: UserPublicInfo(publicKey: 'test_key', userName: 'test', timestamp: 0),
      sponsors: ['127.0.0.1:8888'],
      onNodeChanged: (VillagerNode _node) {
        expect(_node.port, port2);
        if(first) {
          expect(_node.id, '?');
          first = false;
        } else {
          expect(_node.id, 'device2');
        }
      },
      deviceId: 'device1',
      port: port1,
    );
    overlay.start();
  }
  static Future<void> func2() async {
    var overlay = VillageOverlay(
      userInfo: UserPublicInfo(publicKey: 'test_key', userName: 'test', timestamp: 0),
      sponsors: [],
      onNodeChanged: (VillagerNode _node) {
        MyLogger.info('New incoming connection(${_node.ip.toString()}:${_node.port.toString()}, ${_node.id}, ${_node.getStatus()})');
      },
      deviceId: 'device2',
      port: port2,
    );
    overlay.start();
    await Future.delayed(Duration(seconds: 20));
  }
}
