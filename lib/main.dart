// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mesh_note/page/splash_page.dart';
import 'init.dart';
import 'net/p2p_net.dart';
import 'page/mesh_app.dart';

void main(List<String> args) async {
  print('$args');
  if(args.length == 2 && args[0] == 'server') {
    int port = int.tryParse(args[1])?? -1;
    if(port > 0) {
      serverInit();
      runServer();
      return;
    } else {
      print('Invalid server port: ${args[1]}');
      return;
    }
  } else {
    _runApp();
  }
}

void _runApp() async {
  if(Platform.isAndroid || Platform.isIOS) { // Use flutter_native_splash for mobile
    await appInit();
    runApp(const MeshApp());
  } else { // use SplashPage for desktop
    runApp(const SplashPage(onInit: appInit));
  }
}
