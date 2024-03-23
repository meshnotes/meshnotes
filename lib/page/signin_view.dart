import 'package:flutter/material.dart';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
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
  UserPrivateInfo? userPrivateInfo;
  late TextEditingController userNameController;
  late TextEditingController privateKeyController;
  late AnimationController _animationController;
  bool hasName = false;
  bool hasKey = false;

  @override
  void initState() {
    super.initState();
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
      return _buildDialog(context);
    }
    return _buildComplete(context);
  }
  
  Widget _buildDialog(BuildContext context) {
    var column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Please create a new key, or paste an exist private key'),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Enter your name here',
          ),
          controller: userNameController,
        ),
        TextButton.icon(
          icon: const Icon(Icons.add_box_outlined),
          onPressed: hasName? _onCreateNewKey: null,
          label: const Text('Create new key'),
        ),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Optional: copy and paste your private key here',
          ),
          controller: privateKeyController,
        ),
        TextButton.icon(
          icon: const Icon(Icons.paste),
          onPressed: hasName && hasKey? _onLoadKey: null,
          label: const Text('Load exist key'),
        ),
      ],
    );
    return Scaffold(
      body: Align(
        child: Container(
          padding: const EdgeInsets.all(10),
          child: column,
        ),
      ),
    );
  }
  
  Widget _buildComplete(BuildContext context) {
    var icon = const Icon(Icons.check_circle, size: 250, color: Colors.green,);
    var column = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon,
        const Text('Finish setting your private key, please click copy icon on the right and save it'),
        Text('Your name: ${userPrivateInfo!.userName}'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Your key: ${userPrivateInfo!.privateKey}'),
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _onCopyKey,
            ),
          ],
        ),
        TextButton.icon(
          icon: const Icon(Icons.done),
          onPressed: _onComplete,
          label: const Text('OK, I have saved my key'),
        ),
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
      body: animated,
    );
    // return AnimatedBuilder(animation: animation, builder: builder)
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
    final privateKey = privateKeyController.value.text;
    final userName = userNameController.value.text;
    final signing = SigningWrapper.loadKey(privateKey);
    String publicKey = signing.getCompressedPublicKey();
    int now = Util.getTimeStamp();
    _setUserInfo(UserPrivateInfo(publicKey: publicKey, userName: userName, privateKey: privateKey, timestamp: now));
    // print('key=$privateKey');
  }

  void _setUserInfo(UserPrivateInfo userInfo) {
    setState(() {
      userPrivateInfo = userInfo;
      _animationController.reset();
      _animationController.forward();
    });
  }

  void _onCopyKey() {
    var value = userPrivateInfo?.privateKey;
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