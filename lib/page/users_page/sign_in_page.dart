import 'package:flutter/material.dart';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/page/widget_templates.dart';
import '../../mindeditor/user/encrypted_user_private_info.dart';
import '../../util/util.dart';
import 'user_page_template.dart';

class SignInView extends StatefulWidget {
  final Function(EncryptedUserPrivateInfo, String) updateCallback;

  const SignInView({
    super.key,
    required this.updateCallback,
  });

  @override
  State<StatefulWidget> createState() => _SignInViewState();
}

class _SignInViewState extends State<SignInView> with TickerProviderStateMixin {
  static const _maxWidth = 400.0;
  static const _iconSize = 100.0;
  EncryptedUserPrivateInfo? userPrivateInfo;
  String? userPassword;
  late TextEditingController userNameController;
  late TextEditingController passwordController;
  late TextEditingController passwordConfirmController;
  late TextEditingController privateKeyController;
  late AnimationController _animationController;
  late AnimationController _completeAnimationController;
  bool hasName = false;
  bool hasKey = false;
  bool hasPassword = false;
  bool passwordValid = false;
  bool passwordConsistent = false;
  bool _canPop = true;
  bool usePassword = true;
  late _SignInStage _stage;

  @override
  void initState() {
    super.initState();
    _stage = _SignInStage.mainMenu;
    userPrivateInfo = null;
    _animationController = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _completeAnimationController = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    hasName = false;
    hasKey = false;
    hasPassword = false;
    passwordValid = false;
    passwordConsistent = false;
    _initControllers();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _completeAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (userPrivateInfo == null) {
      switch(_stage) {
        case _SignInStage.createKey:
          return _buildCreateKeyPage(context);
        case _SignInStage.loadKey:
          return _buildLoadKeyPage(context);
        default:
          return _buildMainDialog(context);
      }
    }
    return _buildComplete(context);
  }
  
  /// Builds the main welcome dialog with options to create or load an account
  /// This is the initial screen users see when opening the app
  Widget _buildMainDialog(BuildContext context) {
    final topIcon = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        'assets/applogo.png',
        width: _iconSize,
        height: _iconSize,
        fit: BoxFit.contain,
      ),
    );
    
    final cardContent = [
      buildPrimaryButton(
        icon: Icons.note_add_outlined,
        label: 'Create new account',
        onPressed: _gotoCreate,
      ),
      const SizedBox(height: 8),
      _buildSecondaryButton(
        icon: Icons.upload_file_outlined,
        label: 'Load existing account',
        onPressed: _gotoLoad,
      ),
      const SizedBox(height: 8),
      _buildSecondaryButton(
        icon: Icons.rocket_launch_outlined,
        label: 'Just use it',
        onPressed: _justTry,
      ),
    ];
    
    final card = buildCard(
      title: 'Welcome to MeshNotes',
      description: 'Create a new account if you are a first-time user. To access your data from other devices, import your existing account.',
      children: cardContent,
    );
    
    final content = _buildPageContent(
      topIcon: topIcon,
      children: [
        card,
      ],
    );
    
    return _buildPageScaffold(
      context: context,
      title: 'Welcome',
      content: content,
    );
  }

  /// Builds a scaffold with standardized layout for all pages
  /// Handles animations and back navigation consistently
  /// 
  /// Parameters:
  /// - context: The build context
  /// - title: The page title shown in the app bar
  /// - content: The main content widget
  /// - withAnimation: Whether to apply scale animation
  /// - withPopScope: Whether to handle back navigation
  Widget _buildPageScaffold({
    required BuildContext context,
    required String title,
    required Widget content,
    bool withPopScope = false,
    AnimationController? animationController,
  }) {
    Widget body = content;
    
    /// Apply animation if requested
    if (animationController != null) {
      body = AnimatedBuilder(
        animation: animationController,
        builder: (BuildContext context, Widget? child) {
          return ScaleTransition(
            scale: animationController,
            child: child,
          );
        },
        child: body,
      );
    }
    
    /// Add back navigation handling if requested
    if (withPopScope) {
      body = _buildPopScope(context, body);
    }
    
    return Scaffold(
      appBar: WidgetTemplate.buildSimpleAppBar(title),
      body: body,
    );
  }

  /// Creates a PopScope wrapper to handle back navigation
  /// Prevents accidental app exits and manages navigation flow
  Widget _buildPopScope(BuildContext context, Widget child) {
    final popScope = PopScope(
      child: child,
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if(!_canPop) {
          _gotoMain();
          return;
        }
      },
    );
    return popScope;
  }

  /// Builds the account creation page where users enter their name
  /// Generates a new private key based on the provided name
  Widget _buildCreateKeyPage(BuildContext context) {
    const topIcon = Icon(
      Icons.person_add_alt_outlined, 
      size: _iconSize, 
      color: Colors.black54,
    );
    
    final nameField = buildNormalInputField(context, 'Your name', userNameController);
    final passwordField = buildPasswordInputField(context, 'Set your password', passwordController, usePassword);
    final passwordConfirmField = buildPasswordInputField(context, 'Input password again', passwordConfirmController, usePassword);
    final usePasswordCheckbox = _buildNeedPasswordCheckBox();
    final cardContent = [
      nameField,
      const SizedBox(height: 4),
      passwordField,
      const SizedBox(height: 4),
      passwordConfirmField,
      const SizedBox(height: 4),
      usePasswordCheckbox,
      const SizedBox(height: 4),
      passwordErrorMessage(hasPassword, passwordValid, passwordConsistent)?? const SizedBox(height: 16), // After padding, here will show password error message
      const SizedBox(height: 4),
      buildPrimaryButton(
        icon: Icons.note_add_outlined,
        label: 'Create new key',
        onPressed: (hasName && (!usePassword || (hasPassword && passwordConsistent))) ? _onCreateNewKey : null,
      ),
    ];
    
    final card = buildCard(
      title: 'Create Your Account',
      description: 'Please enter your name and password to generate a new key. Make sure to save your key in a secure location.',
      children: cardContent,
    );
    
    final backButton = _buildTextButton(
      icon: Icons.arrow_back,
      label: 'Back to main menu',
      onPressed: _gotoMain,
    );
    
    final content = _buildPageContent(
      topIcon: topIcon,
      children: [
        card,
        // const SizedBox(height: 24),
      ],
      bottom: backButton,
    );
    
    return _buildPageScaffold(
      context: context,
      title: 'Create new account',
      content: content,
      animationController: _animationController,
      withPopScope: true,
    );
  }

  /// Builds the account import page where users can paste their existing key
  /// Allows users to access their account from another device
  Widget _buildLoadKeyPage(BuildContext context) {
    const topIcon = Icon(
      Icons.upload_file_outlined, 
      size: _iconSize, 
      color: Colors.black54,
    );
    
    final nameField = buildNormalInputField(context, 'Your existing key', privateKeyController);
    // final nameField = Container(
    //   decoration: BoxDecoration(
    //     color: Colors.white,
    //     borderRadius: BorderRadius.circular(12),
    //     border: Border.all(color: Colors.grey.withOpacity(0.3)),
    //   ),
    //   child: TextField(
    //     controller: privateKeyController,
    //     decoration: const InputDecoration(
    //       hintText: 'Your existing key',
    //       hintStyle: TextStyle(color: Colors.grey),
    //       contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    //       border: InputBorder.none,
    //     ),
    //     maxLines: 3,
    //   ),
    // );
    final passwordField = buildPasswordInputField(context, 'Input password', passwordController, usePassword);
    // final passwordField = Container(
    //   decoration: BoxDecoration(
    //     color: Colors.white,
    //     borderRadius: BorderRadius.circular(12),
    //     border: Border.all(color: Colors.grey.withOpacity(0.3)),
    //   ),
    //   child: TextField(
    //     controller: passwordController,
    //     obscureText: true,
    //     enabled: usePassword,
    //     decoration: InputDecoration(
    //       hintText: 'Set your password',
    //       hintStyle: TextStyle(color: usePassword ? Colors.grey : Colors.grey.withOpacity(0.5)),
    //       contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    //       border: InputBorder.none,
    //     ),
    //   ),
    // );

    final usePasswordCheckbox = _buildNeedPasswordCheckBox();
    
    final cardContent = [
      nameField,
      const SizedBox(height: 4),
      passwordField,
      const SizedBox(height: 4),
      usePasswordCheckbox,
      const SizedBox(height: 16),
      buildPrimaryButton(
        icon: Icons.upload_file_outlined,
        label: 'Load existing key',
        onPressed: (hasKey && (!usePassword || hasPassword)) ? _onLoadKey : null,
      ),
    ];
    
    final card = buildCard(
      title: 'Import Your Account',
      description: 'Paste your existing key below to access your account and data from another device.',
      children: cardContent,
    );
    
    final backButton = _buildTextButton(
      icon: Icons.arrow_back,
      label: 'Back to main menu',
      onPressed: _gotoMain,
    );
    
    final content = _buildPageContent(
      topIcon: topIcon,
      children: [
        card,
        // const SizedBox(height: 24),
      ],
      bottom: backButton,
    );
    
    return _buildPageScaffold(
      context: context,
      title: 'Load account',
      content: content,
      animationController: _animationController,
      withPopScope: true,
    );
  }
  
  /// Builds the success page shown after account creation or import
  /// Displays the user's key information and allows them to start using the app
  Widget _buildComplete(BuildContext context) {
    const topIcon = Icon(
      Icons.check_circle, 
      size: _iconSize, 
      color: Colors.green,
    );
    
    final keyInfoContainer = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your name: ${userPrivateInfo!.userName}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your key: ${userPrivateInfo!.toBase64().substring(0, 16)}...',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.black54),
                onPressed: _onCopyKey,
                tooltip: 'Copy key',
              ),
            ],
          ),
        ],
      ),
    );
    
    final cardContent = [
      keyInfoContainer,
      const SizedBox(height: 24),
      buildPrimaryButton(
        icon: Icons.done,
        label: 'Let\'s start',
        onPressed: _onComplete,
      ),
    ];
    
    final card = buildCard(
      title: 'Ready to go!',
      description: 'Your account has been set up. Please copy and save your key in a secure location.',
      children: cardContent,
    );
    
    final content = _buildPageContent(
      topIcon: topIcon,
      children: [
        card,
      ],
    );
    
    Widget body = content;
    if (_completeAnimationController.isAnimating) {
      body = AnimatedBuilder(
        animation: _completeAnimationController,
        builder: (BuildContext context, Widget? child) {
          return FadeTransition(
            opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
              CurvedAnimation(
                parent: _completeAnimationController,
                curve: Curves.easeInOut,
              ),
            ),
            child: child,
          );
        },
        child: body,
      );
    }
    
    return _buildPageScaffold(
      context: context,
      title: 'Account Created',
      content: body,
      animationController: _animationController,
      withPopScope: true,
    );
  }

  /// Navigates back to the main menu
  /// Resets the navigation state to allow normal back button behavior
  void _gotoMain() {
    setState(() {
      _stage = _SignInStage.mainMenu;
      _canPop = true;
    });
  }
  /// Navigates to the account creation page
  /// Starts the animation and disables normal back navigation
  void _gotoCreate() {
    setState(() {
      _animationController.reset();
      _animationController.forward();
      _stage = _SignInStage.createKey;
      _canPop = false;
    });
  }
  /// Navigates to the account import page
  /// Starts the animation and disables normal back navigation
  void _gotoLoad() {
    setState(() {
      _animationController.reset();
      _animationController.forward();
      _stage = _SignInStage.loadKey;
      _canPop = false;
    });
  }
  /// Creates a new key based on the user's name
  /// Generates cryptographic keys and stores user information
  void _onCreateNewKey() {
    final signing = SigningWrapper.random();
    String publicKey = signing.getCompressedPublicKey();
    String privateKey = signing.getPrivateKey();
    int now = Util.getTimeStamp();
    String userName = userNameController.value.text;
    String plainPassword = "";
    if(usePassword) {
      plainPassword = passwordController.value.text;
    }
    final userInfo = UserPrivateInfo(publicKey: publicKey, userName: userName, privateKey: privateKey, timestamp: now);
    final password = convertPassword(plainPassword);
    final encryptedUserInfo = generateEncryptedUserInfo(userInfo, password);
    _setUserInfo(encryptedUserInfo, password);
    // print('key=$privateKey');
  }

  /// Loads an existing key from base64 string
  /// Parses the key and sets up the user information
  void _onLoadKey() {
    final base64Str = privateKeyController.value.text;
    String plainPassword = "";
    if(usePassword) {
      plainPassword = passwordController.value.text;
    }
    try {
      var encryptedUserInfo = EncryptedUserPrivateInfo.fromBase64(base64Str);
      final password = convertPassword(plainPassword);
      final userInfo = encryptedUserInfo.getUserPrivateInfo(password);
      if(userInfo == null) {
        throw Exception('Invalid password');
      }
      _setUserInfo(encryptedUserInfo, password);
    } catch (e) {
      // Show error dialog when key parsing fails
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invalid Key'),
          content: const Text('The key you entered is not valid. Please check and try again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  /// Allows users to try the app without creating an account
  /// Creates a guest account with predefined credentials
  void _justTry() {
    final guestUserInfo = UserPrivateInfo.makeGuest(timestamp: Util.getTimeStamp());
    // Guest uses empty password
    final password = convertPassword("");
    var userInfo = generateEncryptedUserInfo(guestUserInfo, password);
    _setUserInfo(userInfo, password, refresh: false);
    _onComplete();
  }

  /// Updates the user information and navigates to the success page
  /// Save password as sha256 of original password
  /// Starts the animation for the transition
  void _setUserInfo(EncryptedUserPrivateInfo userInfo, String password, {bool refresh = true}) {
    userPrivateInfo = userInfo;
    userPassword = password;
    if(refresh) {
      setState(() {
        _animationController.reset();
        _animationController.forward();
        _stage = _SignInStage.complete;
      });
    }
  }

  /// Copies the user's private key to the clipboard
  /// Allows users to save their key for future use
  void _onCopyKey() {
    var value = userPrivateInfo?.toBase64();
    if(value == null) {
      return;
    }
    ClipboardUtil.writeToClipboard(value);
    //TODO: Implement toast notification for key copy confirmation
  }

  /// Completes the sign-in process and starts the main application
  /// Passes the user information to the parent widget
  void _onComplete() {
    if(userPrivateInfo == null || userPassword == null) return;
    setState(() {
      _completeAnimationController.reset();
      _completeAnimationController.forward();
    });
    _completeAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.updateCallback(userPrivateInfo!, userPassword!);
      }
    });
  }

  /// Creates a standardized page content container
  /// Handles layout, scrolling, and spacing consistently
  /// 
  /// Parameters:
  /// - children: The list of widgets to display in the page
  /// - topIcon: Optional icon to display at the top of the page
  Widget _buildPageContent({
    required List<Widget> children,
    Widget? topIcon,
    Widget? bottom,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // const SizedBox(height: 16),
                if (topIcon != null) Container(
                  padding: const EdgeInsets.all(8),
                  child: topIcon,
                ),
                if (topIcon != null) const SizedBox(height: 8),
                ...children,
                // const SizedBox(height: 16),
                if (bottom != null) bottom,
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Creates a secondary action button with consistent styling
  /// Used for alternative actions on pages
  /// 
  /// Parameters:
  /// - icon: The icon to display in the button
  /// - label: The button text
  /// - onPressed: The callback when button is pressed
  Widget _buildSecondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black87,
        side: const BorderSide(color: Colors.black54),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        minimumSize: const Size(double.infinity, 54),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// Creates a text button with consistent styling
  /// Used for tertiary actions like "Back" or "Skip"
  /// 
  /// Parameters:
  /// - icon: The icon to display in the button
  /// - label: The button text
  /// - onPressed: The callback when button is pressed
  /// - mainAxisSize: Controls the button's horizontal size
  Widget _buildTextButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    MainAxisSize mainAxisSize = MainAxisSize.min,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.black54,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: mainAxisSize,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNeedPasswordCheckBox() {
    updateFunc() {
      if (!usePassword) {
        passwordController.clear();
        passwordConfirmController.clear();
        hasPassword = true;
        passwordValid = true;
        passwordConsistent = true;
      } else {
        hasPassword = false;
        passwordValid = false;
        passwordConsistent = false;
      }
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          usePassword = !usePassword;
          updateFunc();
        });
      },
      child: Row(
        children: [
          Checkbox(
            value: usePassword,
            onChanged: (bool? value) {
              setState(() {
                usePassword = value ?? true;
                updateFunc();
              });
            },
          ),
          const Text('Need Password'),
        ],
      ),
    );
  }

  void _initControllers() {
    userNameController = TextEditingController();
    passwordController = TextEditingController();
    passwordConfirmController = TextEditingController();
    privateKeyController = TextEditingController();

    userNameController.addListener(() {
      var value = userNameController.value;
      if(value.text.isNotEmpty && !hasName) {
        setState(() {
          hasName = true;
        });
      }
      if(value.text.isEmpty && hasName) {
        setState(() {
          hasName = false;
        });
      }
    });

    passwordController.addListener(_passwordListener);
    passwordConfirmController.addListener(_passwordListener);

    privateKeyController.addListener(() {
      var value = privateKeyController.value;
      if(value.text.isNotEmpty && !hasKey) {
        setState(() {
          hasKey = true;
        });
      }
      if(value.text.isEmpty && hasKey) {
        setState(() {
          hasKey = false;
        });
      }
    });
  }

  void _passwordListener() {
    var password = passwordController.value;
    var passwordConfirm = passwordConfirmController.value;
    final _hasPassword = password.text.isNotEmpty;
    if(_hasPassword != hasPassword) {
      setState(() {
        hasPassword = _hasPassword;
      });
    }

    final _passwordValid = _hasPassword && passwordIsValid(password.text);
    if(_passwordValid != passwordValid) {
      setState(() {
        passwordValid = _passwordValid;
      });
    }

    final _passwordConsistent = _passwordValid && passwordIsConsistent(password.text, passwordConfirm.text);
    if(_passwordConsistent != passwordConsistent) {
      setState(() {
        passwordConsistent = _passwordConsistent;
      });
    }
  }
}

/// Enum representing the different stages of the sign-in process
/// Controls which view is displayed to the user
enum _SignInStage {
  mainMenu,
  createKey,
  loadKey,
  complete,
}