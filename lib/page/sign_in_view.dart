import 'package:flutter/material.dart';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/page/widget_templates.dart';
import '../mindeditor/setting/constants.dart';
import '../util/util.dart';

class SignInView extends StatefulWidget {
  final Function(UserPrivateInfo) update;

  const SignInView({
    super.key,
    required this.update,
  });

  @override
  State<StatefulWidget> createState() => _SignInViewState();
}

class _SignInViewState extends State<SignInView> with SingleTickerProviderStateMixin {
  static const _maxWidth = 400.0;
  static const _iconSize = 100.0;
  UserPrivateInfo? userPrivateInfo;
  late TextEditingController userNameController;
  late TextEditingController privateKeyController;
  late AnimationController _animationController;
  bool hasName = false;
  bool hasKey = false;
  bool _canPop = true;
  late _SignInStage _stage;

  @override
  void initState() {
    super.initState();
    _stage = _SignInStage.mainMenu;
    userPrivateInfo = null;
    _animationController = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    userNameController = TextEditingController();
    privateKeyController = TextEditingController();
    hasName = false;
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
    hasKey = false;
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
      _buildPrimaryButton(
        icon: Icons.note_add_outlined,
        label: 'Create new account',
        onPressed: _gotoCreate,
      ),
      const SizedBox(height: 16),
      _buildSecondaryButton(
        icon: Icons.upload_file_outlined,
        label: 'Load existing account',
        onPressed: _gotoLoad,
      ),
    ];
    
    final card = _buildCard(
      title: 'Welcome to MeshNotes',
      description: 'Create a new account if you are a first-time user. To access your data from other devices, import your existing account.',
      children: cardContent,
    );
    
    final exploreButton = _buildTextButton(
      icon: Icons.rocket_launch_outlined,
      label: 'Just explore without signing in',
      onPressed: _justTry,
    );
    
    final content = _buildPageContent(
      topIcon: topIcon,
      children: [
        card,
        const SizedBox(height: 24),
        exploreButton,
      ],
    );
    
    return _buildPageScaffold(
      context: context,
      title: 'Welcome',
      content: content,
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
    
    final inputField = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: TextField(
        controller: userNameController,
        decoration: const InputDecoration(
          hintText: 'Your name',
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: InputBorder.none,
        ),
      ),
    );
    
    final cardContent = [
      inputField,
      const SizedBox(height: 24),
      _buildPrimaryButton(
        icon: Icons.note_add_outlined,
        label: 'Create new key',
        onPressed: hasName ? _onCreateNewKey : null,
      ),
    ];
    
    final card = _buildCard(
      title: 'Create Your Account',
      description: 'Please enter your name to generate a new key. Make sure to save your key in a secure location.',
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
        const SizedBox(height: 24),
        backButton,
      ],
    );
    
    return _buildPageScaffold(
      context: context,
      title: 'Create new account',
      content: content,
      withAnimation: true,
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
    
    final inputField = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: TextField(
        controller: privateKeyController,
        decoration: const InputDecoration(
          hintText: 'Your existing key',
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: InputBorder.none,
        ),
        maxLines: 3,
      ),
    );
    
    final cardContent = [
      inputField,
      const SizedBox(height: 24),
      _buildPrimaryButton(
        icon: Icons.upload_file_outlined,
        label: 'Load existing key',
        onPressed: hasKey ? _onLoadKey : null,
      ),
    ];
    
    final card = _buildCard(
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
        const SizedBox(height: 24),
        backButton,
      ],
    );
    
    return _buildPageScaffold(
      context: context,
      title: 'Load account',
      content: content,
      withAnimation: true,
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
      _buildPrimaryButton(
        icon: Icons.done,
        label: 'Let\'s start',
        onPressed: _onComplete,
      ),
    ];
    
    final card = _buildCard(
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
    
    return _buildPageScaffold(
      context: context,
      title: 'Account Created',
      content: content,
      withAnimation: true,
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
    _setUserInfo(userPrivateInfo = UserPrivateInfo(publicKey: publicKey, userName: userName, privateKey: privateKey, timestamp: now));
    // print('key=$privateKey');
  }

  /// Loads an existing key from base64 string
  /// Parses the key and sets up the user information
  void _onLoadKey() {
    final base64Str = privateKeyController.value.text;
    try {
      var userInfo = UserPrivateInfo.fromBase64(base64Str);
      _setUserInfo(userInfo);
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
    const guest = Constants.userNameAndKeyOfGuest;
    userPrivateInfo = UserPrivateInfo(publicKey: guest, userName: guest, privateKey: guest, timestamp: 0);
    _onComplete();
  }

  /// Updates the user information and navigates to the success page
  /// Starts the animation for the transition
  void _setUserInfo(UserPrivateInfo userInfo) {
    setState(() {
      userPrivateInfo = userInfo;
      _animationController.reset();
      _animationController.forward();
      _stage = _SignInStage.complete;
    });
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
    if(userPrivateInfo == null) return;
    widget.update(userPrivateInfo!);
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
    bool withAnimation = false,
    bool withPopScope = false,
  }) {
    Widget body = content;
    
    /// Apply animation if requested
    if (withAnimation) {
      body = AnimatedBuilder(
        animation: _animationController,
        builder: (BuildContext context, Widget? child) {
          return ScaleTransition(
            scale: _animationController,
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

  /// Creates a standardized page content container
  /// Handles layout, scrolling, and spacing consistently
  /// 
  /// Parameters:
  /// - children: The list of widgets to display in the page
  /// - topIcon: Optional icon to display at the top of the page
  Widget _buildPageContent({
    required List<Widget> children,
    Widget? topIcon,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Align(
        child: Container(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                if (topIcon != null) Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: topIcon,
                ),
                if (topIcon != null) const SizedBox(height: 32),
                ...children,
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Creates a standardized card container for content
  /// Provides consistent styling for all information cards
  /// 
  /// Parameters:
  /// - title: The card's main title
  /// - description: The card's descriptive text
  /// - children: Widgets to display in the card (buttons, fields, etc.)
  Widget _buildCard({
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black54,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ...children,
        ],
      ),
    );
  }

  /// Creates a primary action button with consistent styling
  /// Used for the main actions on each page
  /// 
  /// Parameters:
  /// - icon: The icon to display in the button
  /// - label: The button text
  /// - onPressed: The callback when button is pressed
  Widget _buildPrimaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.withOpacity(0.3),
        disabledForegroundColor: Colors.white70,
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
}

/// Enum representing the different stages of the sign-in process
/// Controls which view is displayed to the user
enum _SignInStage {
  mainMenu,
  createKey,
  loadKey,
  complete,
}