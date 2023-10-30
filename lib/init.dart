import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mesh_note/net/init.dart';
import 'package:my_log/my_log.dart';
import 'mindeditor/controller/controller.dart';

Future<void> appInit({bool test=false}) async {
  WidgetsFlutterBinding.ensureInitialized();
  MyLogger.init(name: 'main', debug: false);
  Controller.init(test: test);
  var networkController = await initNet();
  await Controller.instance.initAll(networkController, test: test);
  // 美化标题栏颜色
  if(Controller.instance.environment.isAndroid()) {
    var style = const SystemUiOverlayStyle(statusBarColor: Colors.transparent);
    SystemChrome.setSystemUIOverlayStyle(style);
  }
}

void serverInit({bool test=false}) {
  MyLogger.init(name: 'main');
}