import 'dart:async';
import 'dart:convert';

import 'package:libp2p/overlay/overlay_controller.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:my_log/my_log.dart';
import 'package:test/test.dart';

void main() {
  const int port1 = 8888;
  const int port2 = 4321;
  const deviceId1 = 'device1';
  const deviceId2 = 'device2';

  test('Running application', timeout: Timeout(Duration(seconds: 10)), () async {
    MyLogger.initForTest(name: 'test');
    var completer1 = Completer<bool>();
    var completer2 = Completer<bool>();
    var app1 = MockApp(completer: completer1, appId: 'Application1');
    var app2 = MockApp(completer: completer2, appId: 'Application2');

    bool firstConnected = true;
    var overlay1 = VillageOverlay(
      sponsors: [],
      onNodeChanged: (VillagerNode _node) {
        if(firstConnected) {
          expect(_node.id, '?');
          firstConnected = false;
        } else {
          expect(_node.id, deviceId2);
          app1.setNode(_node);
          app1.test();
        }
      },
      deviceId: deviceId1,
      port: port1,
    );
    var overlay2 = VillageOverlay(
      sponsors: ['127.0.0.1:$port1'],
      onNodeChanged: (VillagerNode _node) {
      },
      deviceId: deviceId2,
      port: port2,
    );

    app1.register(overlay1);
    app2.register(overlay2);

    await overlay1.start();
    await overlay2.start();
    await completer1.future;
    await completer2.future;
  });
}

class MockApp implements ApplicationController {
  static String _appName = 'test';
  VillageOverlay? _overlay;
  Completer<bool> completer;
  VillagerNode? _node;
  String appId;

  MockApp({
    required this.completer,
    required this.appId,
  });

  void register(VillageOverlay overlay) {
    overlay.registerApplication(_appName, this);
    _overlay = overlay;
  }

  @override
  void onData(VillagerNode node, String app, String type, String data) {
    MyLogger.info('$appId: on data');
    expect(type, _testType);
    final testData = TestData.fromJson(jsonDecode(data));
    expect(testData.number, _testNum);
    expect(testData.name, _testName);
    completer.complete(true);
  }

  void test() {
    Future.delayed(Duration(seconds: 1), () {
      MyLogger.info('$appId: end test data');
      expect(_overlay != null, true);
      expect(_node != null, true);
      final appData = TestData(number: _testNum, name: _testName);
      String jsonStr = jsonEncode(appData);
      _overlay!.sendData(this, _node!, _testType, jsonStr);
      completer.complete(true);
    });
  }

  void setNode(VillagerNode n) {
    _node = n;
  }
}

const String _testType = 'test_type';
const int _testNum = 1;
const String _testName = 'abc';

class TestData {
  int number;
  String name;

  TestData({
    required this.number,
    required this.name,
  });

  TestData.fromJson(Map<String, dynamic> map): number = map['num'], name = map['name'];

  Map<String, dynamic> toJson() {
    return {
      'num': number,
      'name': name,
    };
  }
}