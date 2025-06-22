import 'package:flutter/material.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/util/util.dart';
import '../widget_templates.dart';
import 'user_page_template.dart';

class ChangeUserInfoDialog extends StatefulWidget {
  final SimpleUserPrivateInfo userInfo;
  const ChangeUserInfoDialog({super.key, required this.userInfo});

  @override
  State<ChangeUserInfoDialog> createState() => _ChangeUserInfoDialogState();
}

class _ChangeUserInfoDialogState extends State<ChangeUserInfoDialog> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _changePassword = false;
  bool _hasPassword = false;
  bool _nameChanged = false;
  bool _passwordValid = false;
  bool _passwordConsistent = false;
  bool _passwordChanged = false;
  bool _clearPassword = false;
  // late EncryptedUserPrivateInfo _encryptedUserInfo;

  @override
  void initState() {
    super.initState();
    // Check if user currently has a password
    // final controller = Controller();
    // _encryptedUserInfo = controller.getEncryptedUserPrivateInfo()!;
    // _hasCurrentPassword = _encryptedUserInfo.isEncrypted;
    _usernameController.text = widget.userInfo.userName;
    
    // Add listeners to trigger UI rebuilds when text changes
    _usernameController.addListener(_onTextChanged);
    _passwordController.addListener(_onPasswordChanged);
    _confirmPasswordController.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _usernameController.removeListener(_onTextChanged);
    _passwordController.removeListener(_onPasswordChanged);
    _confirmPasswordController.removeListener(_onPasswordChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDialogTitle(),
            const SizedBox(height: 16),
            _buildFormFields(),
            const SizedBox(height: 16),
            passwordErrorMessage(_hasPassword, _passwordValid, _passwordConsistent)?? const SizedBox(height: 16),
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: WidgetTemplate.buildSmallBorderlessButton(context, Icons.close, 'Cancel', () {
            Navigator.of(context).pop();
          }),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: WidgetTemplate.buildSmallBorderlessButton(
            context, 
            Icons.check, 
            'Confirm', 
            _nameChanged || _passwordChanged ? _onConfirm : null,
          ),
        ),
      ],
    );
  }

  Widget _buildFormFields() {
    return Column(
      children: [
        _buildUsernameField(),
        const SizedBox(height: 16),
        _buildPasswordChangeCheckbox(),
        const SizedBox(height: 8),
        _buildClearPasswordCheckbox(),
        const SizedBox(height: 16),
        _buildPasswordField(),
        const SizedBox(height: 16),
        _buildConfirmPasswordField(),
      ],
    );
  }

  void _onConfirm() {
    // Validate password fields only if user wants to change password
    var name = widget.userInfo.userName;
    if(_nameChanged) {
      name = _usernameController.text.trim();
    }
    final now = Util.getTimeStamp();
    final newUserInfo = SimpleUserPrivateInfo(
      publicKey: widget.userInfo.publicKey,
      userName: name,
      privateKey: widget.userInfo.privateKey,
      timestamp: now,
    );
    
    String? password;
    if (_clearPassword) {
      // Clear password - set to empty string
      password = "";
    } else if (_changePassword) {
      // Change password - use entered password
      password = _passwordController.text.trim();
    } else {
      // No password change
      password = null;
    }
    
    // password has three cases:
    // 1. null: no change
    // 2. empty: set password to be empty
    // 3. not empty: set new password
    final encryptedPassword = password == null? null: convertPassword(password);
    final ok = Controller().changeUserInfo(newUserInfo, encryptedPassword);
    if(ok) {
      CallbackRegistry.showToast('User info updated successfully');
      Navigator.of(context).pop();
    } else {
      CallbackRegistry.showToast('Failed to update user info');
    }
  }

  Widget _buildDialogTitle() {
    return const Text(
      'Change User Info',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildUsernameField() {
    return buildNormalInputField(context, 'Username', _usernameController);
  }

  Widget _buildPasswordField() {
    return buildPasswordInputField(context, 'New Password', _passwordController, _changePassword);
  }

  Widget _buildConfirmPasswordField() {
    return buildPasswordInputField(context, 'Confirm Password', _confirmPasswordController, _changePassword);
  }

  Widget _buildPasswordChangeCheckbox() {
    updateFunc(bool? newValue) {
      setState(() {
        if (newValue == true) {
          // Check change password and uncheck clear password
          _changePassword = true;
          _clearPassword = false;
        } else {
          // Uncheck change password
          _changePassword = false;
          // Clear password fields when unchecking
          _passwordController.clear();
          _confirmPasswordController.clear();
        }
      });
      _onPasswordChanged();
    }
    return GestureDetector(
      onTap: () {
        updateFunc(!_changePassword);
      },
      child: Row(
        children: [
          Checkbox(
            value: _changePassword,
            onChanged: (bool? value) {
              updateFunc(value);
            },
          ),
          const SizedBox(width: 8),
          const Text(
            'Change Password',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClearPasswordCheckbox() {
    updateFunc(bool? newValue) async {
      if (newValue == true) {
        // Show confirmation dialog before checking clear password
        final confirmed = await _showClearPasswordConfirmationDialog();
        if (confirmed) {
          setState(() {
            _clearPassword = true;
            _changePassword = false;
            _passwordController.clear();
            _confirmPasswordController.clear();
          });
          _onPasswordChanged();
        }
      } else {
        // Uncheck clear password directly
        setState(() {
          _clearPassword = false;
        });
        _onPasswordChanged();
      }
    }
    return GestureDetector(
      onTap: () async {
        await updateFunc(!_clearPassword);
      },
      child: Row(
        children: [
          Checkbox(
            value: _clearPassword,
            onChanged: (bool? value) async {
              await updateFunc(value);
            },
          ),
          const SizedBox(width: 8),
          const Text(
            'Clear Password',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _showClearPasswordConfirmationDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Clear Password'),
          content: const Text(
            'Are you sure you want to clear your password? '
            'This will remove password protection from your private key. '
            'You can always set a new password later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Clear Password'),
            ),
          ],
        );
      },
    ) ?? false;
  }
  
  void _onTextChanged() {
    // Trigger UI rebuild to update confirm button state
    final userName = _usernameController.text.trim();
    if(userName.isNotEmpty && userName != widget.userInfo.userName) {
      setState(() {
        _nameChanged = true;
      });
    } else {
      setState(() {
        _nameChanged = false;
      });
    }
  }

  void _onPasswordChanged() {
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final hasPassword = password.isNotEmpty;
    final passwordValid = hasPassword && passwordIsValid(password);
    final passwordConsistent = passwordValid && passwordIsConsistent(password, confirmPassword);
    // When clearing password, both fields are empty and _clearPassword is true
    final passwordChanged = _clearPassword || (hasPassword && passwordValid && passwordConsistent);
    
    if(hasPassword != _hasPassword) {
      setState(() {
        _hasPassword = hasPassword;
      });
    }
    if(passwordValid != _passwordValid) {
      setState(() {
        _passwordValid = passwordValid;
      });
    }
    if(passwordConsistent != _passwordConsistent) {
      setState(() {
        _passwordConsistent = passwordConsistent;
      });
    }
    if(passwordChanged != _passwordChanged) {
      setState(() {
        _passwordChanged = passwordChanged;
      });
    }
  }
}
