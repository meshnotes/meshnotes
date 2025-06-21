import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/user/encrypted_user_private_info.dart';
import '../widget_templates.dart';
import 'user_page_template.dart';

class PasswordInputView extends StatefulWidget {
  final EncryptedUserPrivateInfo encryptedUserInfo;
  final Function(EncryptedUserPrivateInfo, String) updateCallback;

  const PasswordInputView({
    super.key,
    required this.encryptedUserInfo,
    required this.updateCallback,
  });

  @override
  State<StatefulWidget> createState() => _PasswordInputViewState();
}

class _PasswordInputViewState extends State<PasswordInputView> with SingleTickerProviderStateMixin {
  static const _maxWidth = 400.0;
  static const _iconSize = 100.0;
  late TextEditingController passwordController;
  bool hasPassword = false;
  String? errorMessage;
  late AnimationController _animationController;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _initControllers();
    _initAnimationController();
  }

  void _initControllers() {
    passwordController = TextEditingController();
    passwordController.addListener(() {
      final _hasPassword = passwordController.text.isNotEmpty;
      if(_hasPassword != hasPassword) {
        setState(() {
          hasPassword = _hasPassword;
          errorMessage = null;
        });
      }
    });
  }

  void _initAnimationController() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.updateCallback(widget.encryptedUserInfo, convertPassword(passwordController.text));
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _tryDecrypt() {
    final password = convertPassword(passwordController.text);
    try {
      final simpleInfo = widget.encryptedUserInfo.getSimpleUserPrivateInfo(password);
      if (simpleInfo != null) {
        setState(() {
          _isAnimating = true;
          errorMessage = null;
        });
        _animationController.forward();
      } else {
        setState(() {
          errorMessage = 'Invalid password';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to decrypt';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildPageScaffold(
      context: context,
      title: 'Enter Password',
      content: _buildPageContent(),
      animationController: _isAnimating ? _animationController : null,
    );
  }

  Widget _buildPasswordInput() {
    final passwordField = buildPasswordInputField(context, 'Set your password', passwordController, true);
    // final passwordField = Container(
    //   decoration: BoxDecoration(
    //     color: Colors.white,
    //     borderRadius: BorderRadius.circular(12),
    //     border: Border.all(color: Colors.grey.withOpacity(0.3)),
    //   ),
    //   child: TextField(
    //     controller: passwordController,
    //     obscureText: true,
    //     decoration: const InputDecoration(
    //       hintText: 'Set your password',
    //       hintStyle: TextStyle(color: Colors.grey),
    //       contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    //       border: InputBorder.none,
    //     ),
    //   ),
    // );
    return passwordField;
  }

  Widget _buildErrorMessage() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        errorMessage!,
        style: const TextStyle(
          color: Colors.red,
        ),
      ),
    );
  }

  Widget _buildCard() {
    return buildCard(
      title: 'Enter Password',
      description: 'Please enter your password to use your account.',
      children: [
        _buildPasswordInput(),
        const SizedBox(height: 16),
        if (errorMessage != null) _buildErrorMessage(),
        buildPrimaryButton(
          icon: Icons.done,
          label: 'OK',
          onPressed: hasPassword ? _tryDecrypt : null,
        ),
      ],
    );
  }

  Widget _buildPageContent() {
    final topIcon = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        'assets/applogo.png',
        width: _iconSize,
        height: _iconSize,
        fit: BoxFit.contain,
      ),
    );

    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              topIcon,
              const SizedBox(height: 32),
              _buildCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageScaffold({
    required BuildContext context,
    required String title,
    required Widget content,
    AnimationController? animationController,
  }) {
    Widget body = content;
    
    /// Apply animation if requested
    if (animationController != null) {
      body = AnimatedBuilder(
        animation: animationController,
        builder: (BuildContext context, Widget? child) {
          return FadeTransition(
            opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
              CurvedAnimation(
                parent: animationController,
                curve: Curves.easeInOut,
              ),
            ),
            child: child,
          );
        },
        child: body,
      );
    }
    
    return Scaffold(
      appBar: WidgetTemplate.buildSimpleAppBar(title),
      body: body,
    );
  }
}