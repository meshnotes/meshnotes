import 'dart:isolate';
import 'net_controller.dart';
import 'net_isolate.dart';

Future<NetworkController> initNet() async {
  var receivePort = ReceivePort();
  var isolate = await Isolate.spawn(netIsolateRunner, receivePort.sendPort);

  var controller = NetworkController(isolate, receivePort);
  return controller;
}
