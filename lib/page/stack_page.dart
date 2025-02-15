import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/setting/setting.dart';
import 'package:mesh_note/mindeditor/view/floating_stack_layer.dart';
import 'package:mesh_note/page/widget_templates.dart';
import 'package:my_log/my_log.dart';
import 'sign_in_view.dart';
import '../mindeditor/controller/controller.dart';
import '../mindeditor/setting/constants.dart';
import 'doc_navigator.dart';
import 'doc_view.dart';

class StackPageView extends StatefulWidget {
  const StackPageView({super.key});

  @override
  State<StatefulWidget> createState() => _StackPageViewState();
}

class _StackPageViewState extends State<StackPageView> {
  final navigationViewKey = GlobalKey();
  final documentViewKey = GlobalKey();
  final _globalPluginLayerKey = GlobalKey<FloatingStackViewState>();
  final _toastLayerKey = GlobalKey<_FloatingToastViewState>();
  final animationDuration = 200;
  final controller = Controller();
  int position = 0;
  double savedScreenWidth = 0;
  bool canPop = true;

  @override
  void initState() {
    super.initState();
    CallbackRegistry.registerShowToast(_showMainToast);
    CallbackRegistry.registerShowGlobalDialog(_showGlobalDialog);
    CallbackRegistry.registerClearGlobalDialog(_clearGlobalDialog);
  }

  @override
  Widget build(BuildContext context) {
    MyLogger.debug('StackPageView: build page, width=${MediaQuery.of(context).size.width}, height=${MediaQuery.of(context).size.height}');
    Widget mainView = _buildMainView(context);
    Widget globalPluginLayer = _buildGlobalPluginLayer(context);
    Widget toastLayer = _buildToastLayer(context);
    final stack = Stack(
      children: [
        mainView,
        globalPluginLayer,
        toastLayer,
      ],
    );
    final popScope = PopScope(
      child: stack,
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        MyLogger.info('StackPageView: pop, didPop=$didPop');
        if(!canPop) {
          _switchToNavigatorView();
          return;
        }
      },
    );
    return popScope;
  }


  Widget _buildMainView(BuildContext context) {
    final smallView = controller.environment.isSmallView(context);
    var userInfo = controller.userPrivateInfo;
    if(userInfo == null) {
      return _buildSignInView(context);
    }
    if(smallView) {
      return _buildForSmallView(context);
    } else {
      return _buildForLargeView(context);
    }
  }

  void _updateUserInfo(UserPrivateInfo userInfo) {
    /// 1. Update user name and key settings
    /// 2. Try to start network again
    /// 3. set state to update UI
    controller.userPrivateInfo = userInfo;
    final base64Str = userInfo.toBase64();
    final userNameSetting = SettingData(
      name: Constants.settingKeyUserInfo,
      displayName: Constants.settingNameUserInfo,
      comment: Constants.settingCommentUserInfo,
      value: base64Str,
    );
    controller.setting.saveSettings([userNameSetting]);
    controller.tryStartingNetwork();
    setState(() {
    });
  }
  Widget _buildSignInView(BuildContext context) {
    return SignInView(
      update: _updateUserInfo,
    );
  }

  Widget _buildForSmallView(BuildContext context) {
    var layout = LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        savedScreenWidth = screenWidth;
        var stack = Stack(
          children: [
            Positioned(
              top: 0,
              left: position * screenWidth,
              width: screenWidth,
              height: screenHeight,
              child: DocumentNavigator(
                key: navigationViewKey,
                smallView: true,
                jumpAction: _switchToDocumentView,
              ),
              // duration: Duration(milliseconds: animationDuration),
            ),
            Positioned(
              top: 0,
              left: (position + 1) * screenWidth,
              width: screenWidth,
              height: screenHeight,
              child: DocumentView(
                key: documentViewKey,
                smallView: true,
                jumpAction: _switchToNavigatorView,
              ),
              // duration: Duration(milliseconds: animationDuration),
            ),
          ],
        );
        return stack;
      }
    );
    final scaffold = Scaffold(
      appBar: _buildAppBar(),
      body: layout,
    );
    return scaffold;
  }
  Widget _buildForLargeView(BuildContext context) {
    final row = Row(
      children: [
        SizedBox(
          width: 240,
          child: DocumentNavigator(
            key: navigationViewKey,
            smallView: false,
            jumpAction: _switchToDocumentView,
          ),
        ),
        Container(
          width: 2,
          color: Colors.grey[100],
        ),
        Expanded(
          child: DocumentView(
            key: documentViewKey,
            smallView: false,
            jumpAction: _switchToNavigatorView,
          ),
        )
      ],
    );
    final scaffold = Scaffold(
      appBar: _buildAppBar(),
      body: row,
    );
    return scaffold;
  }

  AppBar? _buildAppBar() {
    // On large view, there is a divider between navigator and document view, so need a overall app bar to show the status on top
    return AppBar(
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      backgroundColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 0,
    );
  }

  void _switchToDocumentView() {
    setState(() {
      position = -1;
      canPop = false;
    });
  }
  void _switchToNavigatorView() {
    controller.eventTasksManager.triggerUserSwitchToNavigatorEvent();
    setState(() {
      position = 0;
      canPop = true;
    });
  }

  Widget _buildGlobalPluginLayer(BuildContext context) {
    return FloatingStackView(
      key: _globalPluginLayerKey,
    );
  }
  Widget _buildToastLayer(BuildContext context) {
    return _FloatingToastView(
      key: _toastLayerKey,
    );
  }
  
  void _showMainToast(String content) {
    MyLogger.info('showEditorToast: $content');
    _toastLayerKey.currentState?.addToast(content);
  }
  void _showGlobalDialog(String title, Widget child) {
    _globalPluginLayerKey.currentState?.addLayer(child);
  }
  void _clearGlobalDialog() {
    _globalPluginLayerKey.currentState?.clearLayer();
  }
}

class _FloatingToastView extends StatefulWidget {
  const _FloatingToastView({
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _FloatingToastViewState();
}
class _FloatingToastViewState extends State<_FloatingToastView> with TickerProviderStateMixin {
  List<Widget> toasts = [];

  @override
  Widget build(BuildContext context) {
    final column = Column(
      children: [
        Expanded(child: Container(height: double.infinity,),),
        ...toasts,
        Container(height: 16.0,),
      ],
    );
    return WidgetTemplate.buildKeyboardResizableContainer(column);
  }

  void addToast(String content) {
    if(toasts.length >= 3) { // Pop the oldest toast
      toasts.removeAt(0);
    }

    /// 1. animation1 size in
    /// 2. wait for 2 seconds
    /// 3. animation2 fade out
    /// 4. delete toast
    final toast = Container(
      margin: const EdgeInsets.fromLTRB(0, 4.0, 0, 4.0),
      width: double.infinity,
      child: Row(
        children: [
          Expanded(child: Container()),
          Container(
            padding: const EdgeInsets.all(8.0),
            constraints: const BoxConstraints.tightForFinite(),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4.0)),
            alignment: Alignment.center,
            child: Text(
              content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.0,
                fontStyle: FontStyle.normal,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Expanded(child: Container()),
        ],
      ),
    );
    final _animation1 = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    final _animated1 = AnimatedBuilder(
      animation: _animation1,
      builder: (BuildContext context, child) {
        return SizeTransition(
          sizeFactor: _animation1,
          child: child,
        );
      },
      child: toast,
    );
    final _animation2 = AnimationController(vsync: this, duration: const Duration(milliseconds: 500), lowerBound: 0.0, upperBound: 1.0, value: 1.0);
    final _animated2 = AnimatedBuilder(
      animation: _animation2,
      builder: (BuildContext context, child) {
        return FadeTransition(
          opacity: _animation2,
          child: child,
        );
      },
      child: _animated1,
    );
    _animation1.addStatusListener((status) {
      if(status == AnimationStatus.completed) {
        final _ = Timer(const Duration(milliseconds: 2000), () {
          _animation2.reverse();
        });
      }
    });
    _animation2.addStatusListener((status) {
      if(status == AnimationStatus.dismissed) {
        setState(() {
          toasts.remove(_animated2);
        });
      }
    });
    setState(() {
      toasts.add(_animated2);
      _animation1.forward();
    });
  }
}
