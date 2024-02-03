// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter_window_close/flutter_window_close.dart';
import 'package:mesh_note/page/large_screen_view.dart';
import 'package:mesh_note/page/stack_page.dart';
import 'package:mesh_note/page/welcome.dart';
import 'package:my_log/my_log.dart';
import 'init.dart';
import 'mindeditor/controller/controller.dart';
import 'mindeditor/setting/constants.dart';
import 'net/p2p_net.dart';
import 'page/doc_navigator.dart';
import 'page/doc_view.dart';

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
    await appInit();
    runApp(const MeshApp());
  }
}

class MeshApp extends StatefulWidget {
  const MeshApp({Key? key}) : super(key: key);

  @override
  State<MeshApp> createState() => _AppLifecyclePageState();
}

class _AppLifecyclePageState extends State<MeshApp> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    if(Controller.instance.environment.isMobile()) {
      _listener = AppLifecycleListener(
        onStateChange: _onStateChanged,
      );
    } else if(Controller.instance.environment.isDesktop()) {
      FlutterWindowClose.setWindowShouldCloseHandler(_beforeClose);
    }
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return buildStackPage(context);
    // return buildRoutePage(context);
  }

  Widget buildStackPage(BuildContext context) {
    return MaterialApp(
      title: 'MeshNote',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.grey,
      ),
      debugShowCheckedModeBanner: false,
      home: const StackPageView(),
    );
  }

  Widget buildRoutePage(BuildContext context) {
    final routes = {
      Constants.welcomeRouteName: (context) => const WelcomeView(),
      Constants.largeScreenViewName: (context) => const LargeScreenView(),
      Constants.navigatorRouteName: (context) => const DocumentNavigator(smallView: true,),
      Constants.documentRouteName: (context) => DocumentView(smallView: true,),
    };
    return MaterialApp(
      title: 'MeshNote',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.grey,
      ),
      debugShowCheckedModeBanner: false,
      routes: routes,
      initialRoute: Constants.welcomeRouteName,
    );
  }

  Future<void> _onStateChanged(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.detached:
        MyLogger.info('detached');
        break;
      case AppLifecycleState.resumed:
        MyLogger.info('resumed');
        break;
      case AppLifecycleState.inactive:
        MyLogger.info('inactive');
        break;
      case AppLifecycleState.hidden:
        MyLogger.info('hidden');
        break;
      case AppLifecycleState.paused:
        MyLogger.info('paused');
        break;
    }
  }

  Future<bool> _beforeClose() async {
    if(Controller.instance.sendVersionTree()) {
      await Future.delayed(const Duration(seconds: 1));
    }
    final completer = Controller.instance.network.gracefulTerminate();
    await completer.future;
    return true;
  }
}
