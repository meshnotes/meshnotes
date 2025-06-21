import 'package:flutter/material.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';

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

  @override
  void initState() {
    super.initState();
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
        const SizedBox(height: 16),
        _buildPasswordField(),
        const SizedBox(height: 16),
        _buildConfirmPasswordField(),
      ],
    );
  }
  
  void _onConfirm() {
    // Validate password fields only if user wants to change password
    if (_hasPassword) {
      if (_passwordController.text.isEmpty) {
        CallbackRegistry.showToast('Please enter a new password');
        return;
      }
      if (_confirmPasswordController.text.isEmpty) {
        CallbackRegistry.showToast('Please confirm your password');
        return;
      }
      if (_passwordController.text != _confirmPasswordController.text) {
        CallbackRegistry.showToast('Passwords do not match');
        return;
      }
    }
    
    // TODO: Implement the actual user info change logic here
    // You can access the new values:
    // _usernameController.text
    // _passwordController.text (only if _changePassword is true)
    
    Navigator.of(context).pop();
    CallbackRegistry.showToast('User info updated successfully');
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
    updateFunc() {
      if (!_changePassword) {
        // Clear password fields when unchecking
        _passwordController.clear();
        _confirmPasswordController.clear();
      }
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          _changePassword = !_changePassword;
          updateFunc();
        });
      },
      child: Row(
        children: [
          Checkbox(
            value: _changePassword,
            onChanged: (bool? value) {
              setState(() {
                _changePassword = value ?? false;
                updateFunc();
              });
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
    final passwordChanged = hasPassword && passwordValid && passwordConsistent;
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
