import 'package:flutter/material.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/controller/editor_controller.dart';

class UserInfoSettingPage extends StatefulWidget {
  final SimpleUserPrivateInfo userInfo;
  const UserInfoSettingPage({super.key, required this.userInfo});

  @override
  State<StatefulWidget> createState() => _UserInfoSettingPageState();
}

class _UserInfoSettingPageState extends State<UserInfoSettingPage> {
  String _getShortKey(String key) {
    if (key.length <= 12) return key;
    return '${key.substring(0, 6)}...${key.substring(key.length - 6)}';
  }

  void _copyToClipboard() {
    final controller = Controller();
    final encryptedUserInfo = controller.getEncryptedUserPrivateInfo();
    if(encryptedUserInfo == null) return;

    final base64 = encryptedUserInfo.toBase64();
    EditorController.copyTextToClipboard(base64);
    CallbackRegistry.showToast('User info copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        elevation: 8,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Username
              Row(
                children: [
                  const Text(
                    'Name:',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.userInfo.userName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Public Key
              Row(
                children: [
                  const Text(
                    'Public:',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getShortKey(widget.userInfo.publicKey),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Private Key
              Row(
                children: [
                  const Text(
                    'Private:',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getShortKey(widget.userInfo.privateKey),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Buttons
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy User Info'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: () {
                        // TODO: Implement change password functionality
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.lock_outline, size: 18),
                      label: const Text('Change Password'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}