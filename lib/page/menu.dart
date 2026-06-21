import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'version_page.dart';

typedef _MenuActionSpec = ({String value, IconData icon, String text});

/// [RelativeRect] matches [showMenu] / [PopupMenuButton] anchor rules; [overlaySize] is the overlay used for that rect (needed for iPad width clamp).
class _OverflowMenuPlacement {
  const _OverflowMenuPlacement({required this.position, required this.overlaySize});

  final RelativeRect position;
  final Size overlaySize;
}

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
    final showDebug = controller.setting.getBooleanSetting(Constants.settingKeyShowDebugMenu, false);
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
    if(!menuContext.mounted) return;
    final List<_MenuActionSpec> actions = _menuActionSpecs(showDebug);
    if(actions.isEmpty) return;
    final _OverflowMenuPlacement placement = _calculateMenuPosition(menuContext, buttonContext);

    // flutter/flutter#177992: iPadOS can inject bogus pointers that dismiss [showMenu]'s barrier. When fixed upstream, delete the `if` body and always call [_showOverflowMenuWithShowMenu].
    final String? value;
    if(_isIosTabletLayout(menuContext)) {
      value = await _showOverflowMenuIpadosBarrierWorkaround(menuContext, placement, actions);
    } else {
      value = await _showOverflowMenuWithShowMenu(menuContext, placement, actions);
    }

    if(value == null || !menuContext.mounted) return;
    _onSelected(menuContext, value);
  }

  /// Whether the window is laid out as a tablet-sized iOS device (e.g. iPad). Uses [MediaQuery] shortest side ≥ 600, not model ID.
  bool _isIosTabletLayout(BuildContext context) {
    return !kIsWeb && controller.environment.iosReportsAsPad;
  }

  /// Anchor for the overflow menu: button width under the icon, top edge below the button (same convention as [PopupMenuButton] + [showMenu]).
  _OverflowMenuPlacement _calculateMenuPosition(BuildContext menuContext, BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject()! as RenderBox;
    final RenderBox overlay = Overlay.of(menuContext).context.findRenderObject()! as RenderBox;
    final Offset origin = button.localToGlobal(Offset.zero, ancestor: overlay);
    final double pad = UiConstants.menuItemPadding.toDouble();
    final double menuTop = origin.dy + button.size.height + pad;
    final Size overlaySize = overlay.size;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTWH(origin.dx, menuTop, button.size.width, 0),
      Offset.zero & overlaySize,
    );
    return _OverflowMenuPlacement(position: position, overlaySize: overlaySize);
  }

  /// Normal path: Material [showMenu].
  Future<String?> _showOverflowMenuWithShowMenu(BuildContext context, _OverflowMenuPlacement placement, List<_MenuActionSpec> actions) {
    return showMenu<String>(
      context: context,
      position: placement.position,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UiConstants.menuItemBorderRadius),
      ),
      items: _menuItemsFromSpecs(actions),
    );
  }

  /// Workaround path for iPadOS (flutter/flutter#177992): non-dismissible dialog + custom overlay instead of [showMenu].
  /// Uses the same [RelativeRect] as [showMenu]: [RelativeRect.top] → vertical anchor, [RelativeRect.right] → [Positioned.right] (trailing edge aligned with the button).
  Future<String?> _showOverflowMenuIpadosBarrierWorkaround(BuildContext context, _OverflowMenuPlacement placement, List<_MenuActionSpec> actions) {
    return showGeneralDialog<String?>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      transitionBuilder: (BuildContext _, Animation<double> __, Animation<double> ___, Widget child) => child,
      pageBuilder: (BuildContext _, Animation<double> __, Animation<double> ___) {
        return _IpadMainMenuOverlay(
          top: placement.position.top,
          right: placement.position.right.clamp(8, double.infinity),
          overlayWidth: placement.overlaySize.width,
          actions: actions,
        );
      },
    );
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

  List<_MenuActionSpec> _menuActionSpecs(bool showDebug) {
    return [
      if(showDebug) (value: screenShotKey, icon: Icons.camera_alt_outlined, text: 'Screenshot'),
      if(showDebug) (value: searchKey, icon: Icons.manage_search_outlined, text: 'Search'),
      (value: syncKey, icon: Icons.sync_outlined, text: 'Sync'),
      if(menuType == MenuType.editor) (value: deleteKey, icon: Icons.delete_forever_outlined, text: 'Delete'),
      (value: versionKey, icon: Icons.history_outlined, text: 'Version Map'),
      if(showDebug) (value: clearHistoryKey, icon: Icons.warning_amber_outlined, text: 'Clear History'),
    ];
  }

  List<PopupMenuEntry<String>> _menuItemsFromSpecs(List<_MenuActionSpec> actions) {
    return [
      for(final _MenuActionSpec s in actions)
        PopupMenuItem<String>(
          height: UiConstants.menuItemHeight,
          value: s.value,
          child: _menuRowLabel(icon: s.icon, text: s.text),
        ),
    ];
  }
}

Widget _menuRowLabel({required IconData icon, required String text}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: UiConstants.menuItemIconSize,
        color: Colors.grey[700],
      ),
      SizedBox(width: UiConstants.menuItemPadding.toDouble()),
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

/// iPadOS 26+: [showMenu]'s dismissible barrier is closed by bogus pointers (flutter/flutter#177992). This dialog is not barrier-dismissible; a short post-open window ignores outside taps.
class _IpadMainMenuOverlay extends StatefulWidget {
  const _IpadMainMenuOverlay({
    required this.top,
    required this.right,
    required this.overlayWidth,
    required this.actions,
  });

  final double top;
  final double right;
  final double overlayWidth;
  final List<_MenuActionSpec> actions;

  @override
  State<_IpadMainMenuOverlay> createState() => _IpadMainMenuOverlayState();
}

class _IpadMainMenuOverlayState extends State<_IpadMainMenuOverlay> {
  late final DateTime _openedAt;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
  }

  static const Duration _ignoreOutside = Duration(milliseconds: 700);
  static const double _edge = 8;

  void _outsideDown(PointerDownEvent _) {
    if(DateTime.now().difference(_openedAt) < _ignoreOutside) return;
    if(mounted) Navigator.of(context).pop<String?>(null);
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets safe = MediaQuery.paddingOf(context);
    final double top = widget.top < safe.top + _edge ? safe.top + _edge : widget.top;
    final double maxW = widget.overlayWidth - safe.horizontal - 2 * _edge;
    final ShapeBorder shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(UiConstants.menuItemBorderRadius));

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _outsideDown,
          ),
        ),
        Positioned(
          top: top,
          right: widget.right,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: maxW >= 196 ? 196 : maxW, maxWidth: maxW),
            child: Material(
              elevation: 4,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              color: Theme.of(context).colorScheme.surface,
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for(final _MenuActionSpec a in widget.actions)
                      InkWell(
                        onTap: () => Navigator.of(context).pop<String>(a.value),
                        child: SizedBox(
                          height: UiConstants.menuItemHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: _menuRowLabel(icon: a.icon, text: a.text),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
