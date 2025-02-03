import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'version_page.dart';

enum MenuType {
  navigator,
  editor,
}
class MainMenu extends StatelessWidget {
  static const screenShotKey = 'screenshot';
  static const searchKey = 'search';
  static const syncKey = 'sync';
  static const versionKey = 'version';
  static const deleteKey = 'delete';
  static const clearHistoryKey = 'clear_history';
  final Controller controller;
  final MenuType menuType;

  const MainMenu({
    super.key,
    required this.controller,
    required this.menuType,
  });
  
  @override
  Widget build(BuildContext context) {
    final popUpMenuButton = PopupMenuButton(
      icon: const Icon(Icons.menu),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiConstants.menuItemBorderRadius),
      ),
      position: PopupMenuPosition.under,
      offset: const Offset(0, UiConstants.menuItemPadding),
      onSelected: (value) {
        switch(value) {
          case screenShotKey:
            CallbackRegistry.triggerScreenShot();
            break;
          case searchKey:
            //TODO add search code here
            break;
          case syncKey:
            controller.tryToSaveAndSendVersionTree();
            break;
          case versionKey:
            VersionPage.route(context);
            break;
          case deleteKey:
            controller.deleteDocument();
            break;
          case clearHistoryKey:
            controller.clearHistoryVersions();
            break;
        }
      },
      itemBuilder: (BuildContext ctx) {
        return [
          _buildPopupMenu(screenShotKey, Icons.camera_alt_outlined, 'Screenshot'),
          _buildPopupMenu(searchKey, Icons.manage_search_outlined, 'Search'),
          _buildPopupMenu(syncKey, Icons.sync_outlined, 'Sync'),
          if (menuType == MenuType.editor) _buildPopupMenu(deleteKey, Icons.delete_forever_outlined, 'Delete'),
          _buildPopupMenu(versionKey, Icons.history_outlined, 'Version Map'),
          _buildPopupMenu(clearHistoryKey, Icons.warning_amber_outlined, 'Clear History'),
        ];
      },
    );
    return popUpMenuButton;
  }

  PopupMenuItem _buildPopupMenu(String key, IconData icon, String text) {
    return PopupMenuItem(
      height: UiConstants.menuItemHeight,
      value: key,
      child: _buildMenuIconAndText(icon: icon, text: text),
    );
  }

  Widget _buildMenuIconAndText({
    required IconData icon,
    required String text,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: UiConstants.menuItemIconSize,
          color: Colors.grey[700],
        ),
        const SizedBox(width: UiConstants.menuItemPadding),
        Text(
          text,
          style: TextStyle(
            color: Colors.grey[800],
            fontSize: UiConstants.menuItemTextSize,
          ),
        ),
      ],
    );
  }
}