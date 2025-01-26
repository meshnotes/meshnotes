import 'package:flutter/material.dart';
import 'package:flutter_window_close/flutter_window_close.dart';
import 'package:my_log/my_log.dart';

import '../mindeditor/controller/controller.dart';
import '../mindeditor/setting/constants.dart';
import 'doc_navigator.dart';
import 'doc_view.dart';
import 'large_screen_view.dart';
import 'stack_page.dart';
import 'welcome.dart';

class MeshApp extends StatefulWidget {
  const MeshApp({Key? key}) : super(key: key);

  @override
  State<MeshApp> createState() => _AppLifecyclePageState();
}

class _AppLifecyclePageState extends State<MeshApp> {
  late final AppLifecycleListener _listener;
  final stackPageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final controller = Controller();
    if(controller.environment.isMobile()) {
      _listener = AppLifecycleListener(
        onStateChange: _onStateChanged,
      );
    } else if(controller.environment.isDesktop()) {
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
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          surfaceTint: Colors.transparent, // Color of app bar when content scroll up
          seedColor: Colors.grey.shade600,
          brightness: Brightness.light,
          primary: Colors.grey.shade700,
          secondary: Colors.grey.shade500,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.white,
        ),
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
    final controller = Controller();
    if(controller.network.isStarted()) {
      if(controller.tryToSaveAndSendVersionTree()) {
        await Future.delayed(const Duration(seconds: 1));
      }
      final completer = controller.network.gracefulTerminate();
      await completer?.future;
    }
    return true;
  }
}
