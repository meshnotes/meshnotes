import 'package:flutter/material.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/setting/setting.dart';
import 'signin_view.dart';
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
  final animationDuration = 200;
  int position = 0;
  double savedScreenWidth = 0;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final smallView = screenWidth <= Constants.widthThreshold;
    var userInfo = Controller.instance.userPrivateInfo;
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
    final userNameSetting = SettingData(name: Constants.settingKeyUserName, comment: Constants.settingCommentUserName, value: userInfo.userName);
    final userKeySetting = SettingData(name: Constants.settingKeyUserPrivateKey, comment: Constants.settingCommentUserPrivateKey, value: userInfo.privateKey);
    Controller.instance.userPrivateInfo = userInfo;
    Controller.instance.setting.saveSettings([userNameSetting, userKeySetting]);
    Controller.instance.tryStartingNetwork();
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
}