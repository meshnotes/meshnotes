import 'dart:isolate';
import 'package:flutter/services.dart';

import 'net_controller.dart';
import 'net_isolate.dart';

Future<NetworkController> initNet() async {
  var receivePort = ReceivePort();
  var rootToken = RootIsolateToken.instance!;
  var isolate = await Isolate.spawn(netIsolateRunner, IsolateData(sendPort: receivePort.sendPort, token: rootToken));

  var controller = NetworkController(isolate, receivePort);
  return controller;
}
