import 'package:flutter/material.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/controller/editor_controller.dart';
import 'package:mesh_note/page/widget_templates.dart';

import 'change_user_info_dialog.dart';
import 'sign_in_page.dart';

class UserInfoSettingMenu extends StatefulWidget {
  final UserPrivateInfo userInfo;
  final VoidCallback closeCallback;

  const UserInfoSettingMenu({super.key, required this.userInfo, required this.closeCallback});

  @override
  State<StatefulWidget> createState() => _UserInfoSettingMenuState();
}

class _UserInfoSettingMenuState extends State<UserInfoSettingMenu> {
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

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          '$label:',
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    if (widget.userInfo.isGuest()) {
      return Column(
        children: [
          WidgetTemplate.buildSmallBorderlessButton(context, Icons.person_add, 'Create Account', _showCreateAccountDialog),
        ],
      );
    } else {
      return Column(
        children: [
          WidgetTemplate.buildSmallBorderlessButton(context, Icons.copy, 'Copy User Info', _copyToClipboard),
          WidgetTemplate.buildSmallBorderlessButton(context, Icons.lock_outline, 'Change User Info', _showChangeUserInfoDialog),
        ],
      );
    }
  }

  void _showCreateAccountDialog() {
    // Close the current menu first
    widget.closeCallback();
    
    // Show the sign-in view to create a new account
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => SignInView(
        updateCallback: (userInfo, password) {
          // Handle the new account creation
          final controller = Controller();
          controller.setUserPrivateInfo(userInfo, password);
          controller.tryStartingNetwork();
          Navigator.of(context).pop(); // Close the dialog
        },
      ),
    );
  }

  void _showChangeUserInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => ChangeUserInfoDialog(userInfo: widget.userInfo),
    );
  }

  Widget _buildContentCard() {
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
              _buildInfoRow('Name', widget.userInfo.userName),
              const SizedBox(height: 12),
              // Public Key
              _buildInfoRow('Public', _getShortKey(widget.userInfo.publicKey)),
              const SizedBox(height: 12),
              // Private Key
              _buildInfoRow('Private', _getShortKey(widget.userInfo.privateKey)),
              const SizedBox(height: 16),
              // Buttons
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.closeCallback();
      },
      child: Container(
        color: Colors.black.withOpacity(0.3),
        child: Column(
          children: [
            _buildContentCard(),
            const Spacer(), // Push content to top
          ],
        ),
      ),
    );
  }
}
