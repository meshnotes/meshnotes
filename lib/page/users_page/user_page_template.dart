import 'package:flutter/material.dart';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:mesh_note/mindeditor/user/encrypted_user_private_info.dart';

/// Creates a standardized card container for content
/// Provides consistent styling for all information cards
/// 
/// Parameters:
/// - title: The card's main title
/// - description: The card's descriptive text
/// - children: Widgets to display in the card (buttons, fields, etc.)
Widget buildCard({
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
Widget buildPrimaryButton({
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

Widget? passwordErrorMessage(bool hasPassword, bool passwordValid, bool passwordConsistent) {
  if(!hasPassword) {
    return null;
  }
  if(!passwordValid) {
    return const Text('Password must be at least 8 characters long', style: TextStyle(color: Colors.red));
  }
  if(!passwordConsistent) {
    return const Text('Passwords do not match', style: TextStyle(color: Colors.red));
  }
  return null;
}

Widget buildNormalInputField(BuildContext context, String hintText, TextEditingController controller) {
  final inputField = Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.withOpacity(0.3)),
    ),
    child: TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: Colors.grey),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: InputBorder.none,
      ),
    ),
  );
  return inputField;
}
Widget buildPasswordInputField(BuildContext context, String hintText, TextEditingController controller, bool enabled) {
  return _UserPasswordInputField(hintText: hintText, controller: controller, enabled: enabled);
}

class _UserPasswordInputField extends StatefulWidget {
  final String hintText;
  final TextEditingController controller;
  final bool enabled;

  const _UserPasswordInputField({
    required this.hintText,
    required this.controller,
    required this.enabled,
  });

  @override
  State<_UserPasswordInputField> createState() => _UserPasswordInputFieldState();
}
class _UserPasswordInputFieldState extends State<_UserPasswordInputField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    final passwordField = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: TextField(
        controller: widget.controller,
        obscureText: _obscureText,
        enabled: widget.enabled,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(color: widget.enabled ? Colors.grey : Colors.grey.withOpacity(0.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureText ? Icons.visibility : Icons.visibility_off,
              color: widget.enabled ? Colors.grey : Colors.grey.withOpacity(0.5),
            ),
            onPressed: () {
              setState(() {
                _obscureText = !_obscureText;
              });
            },
          ),
        ),
      ),
    );
    return passwordField;
  }
}

bool passwordIsValid(String password) {
  return password.length >= 8;
}
bool passwordIsConsistent(String password, String passwordConfirm) {
  return password == passwordConfirm;
}