import 'package:flutter/foundation.dart';
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

  /// iPadOS 26+ can deliver a synthetic touch right after opening a popup; a short delay avoids the barrier seeing it (see flutter/flutter#177992).
  static const Duration _iosMenuOpenDelay = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final showDebug = controller.setting.getSetting(Constants.settingKeyShowDebugMenu)?.toLowerCase() == 'true';
    return Builder(
      builder: (BuildContext buttonContext) {
        return IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _openMenu(context, buttonContext, showDebug),
        );
      },
    );
  }

  Future<void> _openMenu(BuildContext menuContext, BuildContext buttonContext, bool showDebug) async {
    if(!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await Future<void>.delayed(_iosMenuOpenDelay);
    }
    if(!menuContext.mounted) return;
    final RenderBox button = buttonContext.findRenderObject()! as RenderBox;
    final RenderBox overlay = Overlay.of(menuContext).context.findRenderObject()! as RenderBox;
    final Offset origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    final double pad = UiConstants.menuItemPadding.toDouble();
    final RelativeRect position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + button.size.height + pad,
      overlay.size.width, // - origin.dx,
      overlay.size.height - origin.dy - button.size.height - pad,
    );
    final String? value = await showMenu<String>(
      context: menuContext,
      position: position,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiConstants.menuItemBorderRadius),
      ),
      items: _menuItems(showDebug),
    );
    if(value == null || !menuContext.mounted) return;
    _onSelected(menuContext, value);
  }

  void _onSelected(BuildContext context, String value) {
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
  }

  List<PopupMenuEntry<String>> _menuItems(bool showDebug) {
    return [
      if(showDebug) _buildPopupMenu(screenShotKey, Icons.camera_alt_outlined, 'Screenshot'),
      if(showDebug) _buildPopupMenu(searchKey, Icons.manage_search_outlined, 'Search'),
      _buildPopupMenu(syncKey, Icons.sync_outlined, 'Sync'),
      if(menuType == MenuType.editor) _buildPopupMenu(deleteKey, Icons.delete_forever_outlined, 'Delete'),
      _buildPopupMenu(versionKey, Icons.history_outlined, 'Version Map'),
      if(showDebug) _buildPopupMenu(clearHistoryKey, Icons.warning_amber_outlined, 'Clear History'),
    ];
  }

  PopupMenuItem<String> _buildPopupMenu(String key, IconData icon, String text) {
    return PopupMenuItem<String>(
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
