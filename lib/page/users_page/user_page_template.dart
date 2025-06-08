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

String convertPassword(String plainPassword) {
  return (plainPassword == "")? "": HashUtil.hashText(plainPassword);
}

EncryptedUserPrivateInfo generateUserInfo(SimpleUserPrivateInfo userInfo, String password) {
  final encryptedUserInfo = EncryptedUserPrivateInfo.fromSimpleUserPrivateInfoAndPassword(userInfo, password);
  return encryptedUserInfo;
}
