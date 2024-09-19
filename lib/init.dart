import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_log/my_log.dart';
import 'mindeditor/controller/controller.dart';

Future<void> appInit() async {
  WidgetsFlutterBinding.ensureInitialized();
  MyLogger.init(name: 'main', debug: false);
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