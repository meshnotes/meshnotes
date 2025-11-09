import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_log/my_log.dart';
import 'mindeditor/controller/controller.dart';

Future<void> appInit() async {
  WidgetsFlutterBinding.ensureInitialized();
  const isProduct = bool.fromEnvironment('dart.vm.product');
  MyLogger.init(name: 'main', debug: !isProduct);
  final controller = Controller();
  await controller.initAll();
  // Make title bar looks better
  if(controller.environment.isAndroid()) {
    var style = const SystemUiOverlayStyle(statusBarColor: Colors.transparent);
    SystemChrome.setSystemUIOverlayStyle(style);
  }
}

void serverInit({bool test=false}) {
  if(test) {
    MyLogger.init(name: 'test', usePrint: true);
  } else {
    MyLogger.init(name: 'main');
  }
}