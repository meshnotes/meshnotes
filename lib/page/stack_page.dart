import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/user/encrypted_user_private_info.dart';
import 'package:mesh_note/page/widget_templates.dart';
import 'package:my_log/my_log.dart';
import 'users_page/input_password_page.dart';
import 'users_page/sign_in_page.dart';
import '../mindeditor/controller/controller.dart';
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
  }

  @override
  Widget build(BuildContext context) {
    MyLogger.debug('StackPageView: build page, width=${MediaQuery.of(context).size.width}, height=${MediaQuery.of(context).size.height}');
    final mainView = _buildMainView(context);
    final globalPluginLayer = _buildGlobalPluginLayer(context);
    final toastLayer = _buildToastLayer(context);
    final stack = Stack(
      children: [
        mainView,
        globalPluginLayer,
        toastLayer,
      ],
    );
    return stack;
  }


  Widget _buildMainView(BuildContext context) {
    final smallView = controller.environment.isSmallView(context);
    var userInfo = controller.getUserPrivateInfo();
    // If user info is not set, two possible reasons:
    // 1. There is no user private key - in this case, the encrypted user private info is also null
    // 2. Password error - in this case, the encrypted user private info is not null
    // In the first case, we need to show the sign in view
    // In the second case, we need to let user enter the correct password
    if(userInfo == null) {
      controller.setLoggingInState();
      var encryptedUserInfo = controller.getEncryptedUserPrivateInfo();
      if(encryptedUserInfo != null) {
        // Password error
        MyLogger.info('StackPageView: build main view, password error');
        return _buildPasswordInputView(context, encryptedUserInfo);
      } else {
        // No user private key yet
        MyLogger.info('StackPageView: build main view, no user private key');
        return _buildSignInView(context);
      }
    }
    controller.setRunningState();
    Widget view;
    if(smallView) {
      view = _buildForSmallView(context);
    } else {
      view = _buildForLargeView(context);
    }
    final popScope = PopScope(
      child: view,
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

  void _updateUserInfo(EncryptedUserPrivateInfo userInfo, String password) {
    /// 1. Update user info and password settings
    /// 2. Try to start network again
    /// 3. Set state to update UI
    controller.setUserPrivateInfo(userInfo, password);
    // Try to start network
    controller.tryStartingNetwork();
    // Update UI
    setState(() {
    });
  }
  Widget _buildSignInView(BuildContext context) {
    return SignInView(
      updateCallback: _updateUserInfo,
    );
  }
  Widget _buildPasswordInputView(BuildContext context, EncryptedUserPrivateInfo encryptedUserInfo) {
    return PasswordInputView(
      encryptedUserInfo: encryptedUserInfo,
      updateCallback: _updateUserInfo,
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
    return controller.pluginManager.buildGlobalButtons(controller: controller);
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
