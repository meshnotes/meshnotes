import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/setting/setting.dart';
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
  final _toastLayerKey = GlobalKey<_FloatingToastViewState>();
  final animationDuration = 200;
  final controller = Controller();
  int position = 0;
  double savedScreenWidth = 0;

  @override
  void initState() {
    super.initState();
    CallbackRegistry.registerShowToast(_showMainToast);
  }

  @override
  Widget build(BuildContext context) {
    MyLogger.debug('StackPageView: build page, width=${MediaQuery.of(context).size.width}, height=${MediaQuery.of(context).size.height}');
    Widget mainView = _buildMainView(context);
    Widget toastLayer = _buildToastLayer(context);
    return Stack(
      children: [
        mainView,
        toastLayer,
      ],
    );
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
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
  Widget _buildForLargeView(BuildContext context) {
    return Row(
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
  }

  void _switchToDocumentView() {
    setState(() {
      position = -1;
    });
  }
  void _switchToNavigatorView() {
    setState(() {
      position = 0;
    });
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
    final stack = Column(
      children: [
        Expanded(child: Container(height: double.infinity,),),
        ...toasts,
        Container(height: 16.0,),
      ],
    );
    return stack;
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
