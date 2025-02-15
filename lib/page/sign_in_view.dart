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
  static const titleStyle = TextStyle(
    fontSize: 22.0,
    color: Colors.black54,
  );
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
  
  Widget _buildMainDialog(BuildContext context) {
    var column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 5,),
        const Icon(Icons.outlined_flag, size: _iconSize, color: Colors.black54,),
        const Spacer(flex: 1,),
        const Text(
          'You need a personal key, or load an exist one. This key is used to encrypt your data, and identify you to synchronize data between your own devices.',
          style: titleStyle,
        ),
        const Spacer(flex: 3,),
        WidgetTemplate.buildDefaultButton(context, Icons.note_add_outlined, 'Create a new key', _gotoCreate),
        WidgetTemplate.buildNormalButton(Icons.upload_file_outlined, 'Load an exist key', _gotoLoad),
        WidgetTemplate.buildInsignificantButton(Icons.person_off_outlined, 'No, I just want to have a try', _justTry),
        const Spacer(flex: 1,),
      ],
    );
    return Scaffold(
      appBar: _buildAppBar('Welcome'),
      body: Container(
        padding: const EdgeInsets.all(16),
        child: column,
      ),
    );
  }

  AppBar _buildAppBar(String title) {
    return AppBar(
      title: Text(title),
    );
  }

  Widget _buildCreateKeyPage(BuildContext context) {
    var column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 5,),
        const Icon(Icons.person_add_alt_outlined, size: _iconSize, color: Colors.black54,),
        const Spacer(flex: 1,),
        const Text(
          'Please enter your name to generate a new key, and keep it as a secret',
          style: titleStyle,
        ),
        const Spacer(flex: 3,),
        WidgetTemplate.buildNormalInputField('your name', userNameController),
        WidgetTemplate.buildNormalButton(Icons.note_add_outlined, 'Create new key', hasName? _onCreateNewKey: null),
        const Spacer(flex: 1,),
        WidgetTemplate.buildInsignificantButton(Icons.arrow_back, 'Back', _gotoMain),
        const Spacer(flex: 1,),
      ],
    );
    var animated = AnimatedBuilder(
      animation: _animationController,
      builder: (BuildContext context, Widget? child) {
        return ScaleTransition(
          scale: _animationController,
          child: child,
        );
      },
      child: column,
    );
    return Scaffold(
      appBar: _buildAppBar('Create your key'),
      body: Align(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Container(
            padding: const EdgeInsets.all(10),
            child: animated,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadKeyPage(BuildContext context) {
    var column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 5,),
        const Icon(Icons.person_add_alt_outlined, size: _iconSize, color: Colors.black54,),
        const Spacer(flex: 1,),
        const Text(
          'Paste your existing key here to load',
          style: titleStyle,
        ),
        const Spacer(flex: 3,),
        WidgetTemplate.buildNormalInputField('Your old key', privateKeyController),
        WidgetTemplate.buildNormalButton(Icons.upload_file_outlined, 'Load exist key', hasKey? _onLoadKey: null,),
        const Spacer(flex: 1,),
        WidgetTemplate.buildInsignificantButton(Icons.arrow_back, 'Back', _gotoMain),
        const Spacer(flex: 1,),
      ],
    );
    var animated = AnimatedBuilder(
      animation: _animationController,
      builder: (BuildContext context, Widget? child) {
        return ScaleTransition(
          scale: _animationController,
          child: child,
        );
      },
      child: column,
    );
    return Scaffold(
      appBar: _buildAppBar('Load your key'),
      body: Align(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Container(
            padding: const EdgeInsets.all(10),
            child: animated,
          ),
        ),
      ),
    );
  }
  
  Widget _buildComplete(BuildContext context) {
    var icon = const Icon(Icons.check_circle, size: _iconSize, color: Colors.green,);
    var column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(flex: 2,),
        icon,
        const Spacer(flex: 1,),
        const Text(
          'Finish setting your private key, please click copy icon on the right and save it',
          style: titleStyle,
        ),
        Container(
          alignment: Alignment.centerLeft,
          child: Text('Your name: ${userPrivateInfo!.userName}'),
        ),
        Row(
          // mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text('Your key info: ${userPrivateInfo!.toBase64().substring(0, 16)}...'),
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _onCopyKey,
            ),
          ],
        ),
        TextButton.icon(
          icon: const Icon(Icons.done),
          onPressed: _onComplete,
          label: const Text('OK, I have already saved my key'),
        ),
        const Spacer(flex: 2,),
      ],
    );
    var container = Container(
      padding: const EdgeInsets.all(10),
      alignment: Alignment.center,
      child: column,
    );
    var animated = AnimatedBuilder(
      animation: _animationController,
      builder: (BuildContext context, Widget? child) {
        return ScaleTransition(
          scale: _animationController,
          child: child,
        );
      },
      child: container,
    );
    return Scaffold(
      body: Align(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: animated,
        ),
      ),
    );
    // return AnimatedBuilder(animation: animation, builder: builder)
  }

  void _gotoMain() {
    setState(() {
      _stage = _SignInStage.mainMenu;
    });
  }
  void _gotoCreate() {
    setState(() {
      _animationController.reset();
      _animationController.forward();
      _stage = _SignInStage.createKey;
    });
  }
  void _gotoLoad() {
    setState(() {
      _animationController.reset();
      _animationController.forward();
      _stage = _SignInStage.loadKey;
    });
  }
  void _onCreateNewKey() {
    final signing = SigningWrapper.random();
    String publicKey = signing.getCompressedPublicKey();
    String privateKey = signing.getPrivateKey();
    int now = Util.getTimeStamp();
    String userName = userNameController.value.text;
    _setUserInfo(userPrivateInfo = UserPrivateInfo(publicKey: publicKey, userName: userName, privateKey: privateKey, timestamp: now));
    // print('key=$privateKey');
  }

  void _onLoadKey() {
    final base64Str = privateKeyController.value.text;
    var userInfo = UserPrivateInfo.fromBase64(base64Str);
    _setUserInfo(userInfo);
    // print('key=$privateKey');
  }

  void _justTry() {
    const guest = Constants.userNameAndKeyOfGuest;
    userPrivateInfo = UserPrivateInfo(publicKey: guest, userName: guest, privateKey: guest, timestamp: 0);
    _onComplete();
  }

  void _setUserInfo(UserPrivateInfo userInfo) {
    setState(() {
      userPrivateInfo = userInfo;
      _animationController.reset();
      _animationController.forward();
      _stage = _SignInStage.complete;
    });
  }

  void _onCopyKey() {
    var value = userPrivateInfo?.toBase64();
    if(value == null) {
      return;
    }
    ClipboardUtil.writeToClipboard(value);
    //TODO send a toast
  }

  void _onComplete() {
    if(userPrivateInfo == null) return;
    widget.update(userPrivateInfo!);
  }
}

enum _SignInStage {
  mainMenu,
  createKey,
  loadKey,
  complete,
}