import 'package:flutter/material.dart';
import 'floating_stack_layer.dart';
import 'floating_stack_reposition_layer.dart';

class FloatingViewManager {
  late Widget _selectionLayer;
  late Widget _pluginTipsLayer;
  late Widget _popupMenuLayer;
  late Widget _pluginDialogLayer;
  final _selectionKey = GlobalKey<FloatingStackViewState>();
  final _pluginTipsKey = GlobalKey<FloatingStackViewState>();
  final _popupMenuKey = GlobalKey<FloatingStackRepositionViewState>();
  final _pluginDialogKey = GlobalKey<FloatingStackViewState>();
  Size _popupMenuSize = const Size(0, 0);

  FloatingViewManager() {
    _selectionLayer = _buildSelectionLayer();
    _pluginTipsLayer = _buildExtraLayer();
    _popupMenuLayer = _buildPopupMenuLayer();
    _pluginDialogLayer = _buildPluginDialogLayer();
  }

  List<Widget> getFloatingLayersForEditor() {
    return [
      _selectionLayer,
      _popupMenuLayer,
      _pluginTipsLayer,
      _pluginDialogLayer,
    ];
  }
  
  void showBlockTips(BuildContext context, String content, LayerLink layerLink) {
    var tipsWidget = _TipsDialog(
      content: content,
      layerLink: layerLink,
      closeCallback: () {
        clearBlockTips();
      },
    );
    _pluginTipsKey.currentState?.addLayer(tipsWidget);
  }
  void clearBlockTips() {
    _pluginTipsKey.currentState?.clearLayer();
  }
  
  void addCursorHandle(Widget handle) {
    _selectionKey.currentState?.addLayer(handle);
  }
  void addSelectionHandles(Widget handle1, Widget handle2) {
    _selectionKey.currentState?.addLayers(handle1, handle2);
  }
  void removeSelectionHandles(Widget handle1, Widget handle2) {
    _selectionKey.currentState?.removeLayer(handle1);
    _selectionKey.currentState?.removeLayer(handle2);
  }
  void clearAllHandles() {
    _selectionKey.currentState?.clearLayer();
  }

  Offset? convertGlobalOffsetToSelectionLayer(Offset global) {
    final render = _selectionKey.currentContext?.findRenderObject() as RenderBox?;
    return render?.globalToLocal(global);
  }
  Offset? convertGlobalOffsetToPopupMenuLayer(Offset global) {
    final render = _popupMenuKey.currentContext?.findRenderObject() as RenderBox?;
    return render?.globalToLocal(global);
  }

  void addPopupMenu(String id, Offset position, Widget menu) {
    _popupMenuKey.currentState?.addLayer(id, position, menu);
  }
  void updatePopupMenuPosition(String id, Offset position) {
    _popupMenuKey.currentState?.updatePosition(id, position);
  }
  void removePopupMenu(String id) {
    _popupMenuKey.currentState?.removeLayer(id);
  }
  void clearPopupMenu() {
    _popupMenuKey.currentState?.clearLayer();
  }

  void updatePopupMenuSize(double width, double height) {
    _popupMenuSize = Size(width, height);
  }
  Size getPopupMenuSize() {
    return Size(_popupMenuSize.width, _popupMenuSize.height);
  }

  void showPluginDialog(Widget dialog) {
    _pluginDialogKey.currentState?.addLayer(dialog);
  }
  void clearPluginDialog() {
    _pluginDialogKey.currentState?.clearLayer();
  }

  Widget _buildSelectionLayer() {
    return FloatingStackView(
      key: _selectionKey,
    );
  }
  Widget _buildExtraLayer() {
    return FloatingStackView(
      key: _pluginTipsKey,
    );
  }
  Widget _buildPopupMenuLayer() {
    return FloatingStackRepositionView(
      key: _popupMenuKey,
    );
  }
  Widget _buildPluginDialogLayer() {
    return FloatingStackView(
      key: _pluginDialogKey,
    );
  }
}

class _TipsDialog extends StatefulWidget {
  final String content;
  final LayerLink layerLink;
  final Function() closeCallback;

  const _TipsDialog({
    required this.content,
    required this.layerLink,
    required this.closeCallback,
  });

  @override
  State<StatefulWidget> createState() => _TipsDialogState();
}

class _TipsDialogState extends State<_TipsDialog> with SingleTickerProviderStateMixin {
  late AnimationController _animation;
  double dragStart = 0;

  @override
  void initState() {
    _animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _animation.addStatusListener((status) {
      if(status == AnimationStatus.dismissed) {
        widget.closeCallback();
      }
    });
    _animation.forward();
    super.initState();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var scrollable = Scrollbar(
      child: SingleChildScrollView(
        child: Text(widget.content, style: Theme.of(context).textTheme.bodyMedium,),
      ),
    );
    var container = Container(
      padding: const EdgeInsets.all(8.0),
      child: scrollable,
    );
    var list = ListView(
      shrinkWrap: true,
      children: [
        container,
      ],
    );
    var box = Container(
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: Colors.green[100],
        borderRadius: BorderRadius.circular(16.0),
      ),
      constraints: const BoxConstraints(
        maxHeight: 150,
        minHeight: 0,
      ),
      width: 200,
      // height: 300,
      child: list,
    );
    var gesture = GestureDetector(
      onHorizontalDragStart: (DragStartDetails details) {
        dragStart = details.globalPosition.dx;
      },
      onHorizontalDragUpdate: (DragUpdateDetails details) {
        double delta = details.globalPosition.dx - dragStart;
        if(delta > 30.0) {
          dragStart = 0.0;
          closeBlockTips();
        }
      },
      child: box,
    );
    var child = CompositedTransformFollower(
      link: widget.layerLink,
      targetAnchor: Alignment.centerRight,
      followerAnchor: Alignment.centerRight,
      child: gesture,
    );
    var result = Container(
      padding: const EdgeInsets.all(8.0),
      alignment: Alignment.centerRight,
      child: child,
    );
    var animated = AnimatedBuilder(
      animation: _animation,
      builder: (BuildContext context, child) {
        return FadeTransition(
          opacity: _animation,
          child: child,
        );
      },
      child: result,
    );
    return animated;
  }

  void startBlockTips() {
    _animation.forward();
  }
  void closeBlockTips() {
    // widget.closeCallback();
    _animation.reverse();
  }
}