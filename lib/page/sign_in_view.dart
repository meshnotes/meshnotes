import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
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
          return _buildCreateKey(context);
        case _SignInStage.loadKey:
          return _buildLoadKey(context);
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
          'You have to create your personal key, or load an exist one',
          style: titleStyle,
        ),
        const Spacer(flex: 3,),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4.0),
          decoration: BoxDecoration(
            color: Colors.blueGrey[100],
            borderRadius: const BorderRadius.all(Radius.circular(8.0)),
          ),
          margin: const EdgeInsets.all(4.0),
          child: TextButton.icon(
            icon: const Icon(Icons.note_add_outlined),
            onPressed: _gotoCreate,
            label: const Text('Create a new key'),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4.0),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey, width: 1.0),
            borderRadius: const BorderRadius.all(Radius.circular(8.0)),
          ),
          margin: const EdgeInsets.all(4.0),
          child: TextButton.icon(
            icon: Icon(Icons.upload_file_outlined, color: Colors.grey[600],),
            onPressed: _gotoLoad,
            label: Text('Load an exist key', style: TextStyle(color: Colors.grey[600]),),
          ),
        ),
        TextButton.icon(
          icon: Icon(Icons.person_off_outlined, color: Colors.grey[600],),
          onPressed: _justTry,
          label: Text('No, I just want to have a try', style: TextStyle(color: Colors.grey[600]),),
        ),
        const Spacer(flex: 1,),
      ],
    );
    return Scaffold(
      body: Align(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Container(
            padding: const EdgeInsets.all(10),
            child: column,
          ),
        ),
      ),
    );
  }

  Widget _buildCreateKey(BuildContext context) {
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
        CupertinoTextField(
          placeholder: 'your name',
          controller: userNameController,
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4.0),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey, width: 1.0),
            borderRadius: const BorderRadius.all(Radius.circular(8.0)),
          ),
          margin: const EdgeInsets.all(4.0),
          child: TextButton.icon(
            icon: const Icon(Icons.note_add_outlined),
            onPressed: hasName? _onCreateNewKey: null,
            label: const Text('Create new key'),
          ),
        ),
        const Spacer(flex: 1,),
        TextButton.icon(
          icon: Icon(Icons.arrow_back, color: Colors.grey[600],),
          onPressed: _gotoMain,
          label: Text('Back', style: TextStyle(color: Colors.grey[600]),),
        ),
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

  Widget _buildLoadKey(BuildContext context) {
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
        CupertinoTextField(
          placeholder: 'Your old key',
          controller: privateKeyController,
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4.0),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey, width: 1.0),
            borderRadius: const BorderRadius.all(Radius.circular(8.0)),
          ),
          margin: const EdgeInsets.all(4.0),
          child: TextButton.icon(
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: hasKey? _onLoadKey: null,
            label: const Text('Load exist key'),
          ),
        ),
        const Spacer(flex: 1,),
        TextButton.icon(
          icon: Icon(Icons.arrow_back, color: Colors.grey[600],),
          onPressed: _gotoMain,
          label: Text('Back', style: TextStyle(color: Colors.grey[600]),),
        ),
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