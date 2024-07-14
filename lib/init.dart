import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mesh_note/net/init.dart';
import 'package:my_log/my_log.dart';
import 'mindeditor/controller/controller.dart';

Future<void> appInit({bool test=false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  if(test) {
    MyLogger.init(name: 'test', debug: false, usePrint: true);
  } else {
    MyLogger.init(name: 'main', debug: false);
  }
  Controller.initDb(test: test);
  var networkController = await initNet();
  await Controller.instance.initAll(networkController, test: test);
  // Make title bar looks better
  if(Controller.instance.environment.isAndroid()) {
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