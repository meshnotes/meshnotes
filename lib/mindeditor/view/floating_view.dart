import 'dart:async';
import 'package:flutter/material.dart';

class FloatingViewManager {
  late Widget _selectionLayer;
  late Widget _pluginTipsLayer;
  late Widget _toastLayer;
  final _selectionKey = GlobalKey<_FloatingStackViewState>();
  final _pluginTipsKey = GlobalKey<_FloatingStackViewState>();
  final _toastLayerKey = GlobalKey<_FloatingToastViewState>();

  FloatingViewManager() {
    _selectionLayer = _buildSelectionLayer();
    _pluginTipsLayer = _buildPluginTipsLayer();
    _toastLayer = _buildToastLayer();
  }

  void showBlockTips(BuildContext context, String content, LayerLink layerLink) {
    var tipsWidget = _TipsDialog(
      content: content,
      layerLink: layerLink,
      closeCallback: () {
        _pluginTipsKey.currentState?.clearLayer();
      },
    );
    _pluginTipsKey.currentState?.addLayer(tipsWidget);
  }

  void showEditorToast(String content) {
    _toastLayerKey.currentState?.addToast(content);
  }

  List<Widget> getWidgets() {
    return [
      _selectionLayer,
      _pluginTipsLayer,
      _toastLayer,
    ];
  }

  void addSelectionHandles(Widget handle1, Widget handle2) {
    _selectionKey.currentState?.addLayer(handle1);
    _selectionKey.currentState?.addLayer(handle2);
  }
  void removeSelectionHandles(Widget handle1, Widget handle2) {
    _selectionKey.currentState?.removeLayer(handle1);
    _selectionKey.currentState?.removeLayer(handle2);
  }

  Offset? convertGlobalOffsetToSelectionLayer(Offset global) {
    final render = _selectionKey.currentContext?.findRenderObject() as RenderBox?;
    return render?.globalToLocal(global);
  }

  Widget _buildSelectionLayer() {
    return _FloatingStackView(
      key: _selectionKey,
    );
  }
  Widget _buildPluginTipsLayer() {
    return _FloatingStackView(
      key: _pluginTipsKey,
    );
  }
  Widget _buildToastLayer() {
    return _FloatingToastView(
      key: _toastLayerKey,
    );
  }
}

class _FloatingStackView extends StatefulWidget {
  const _FloatingStackView({
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _FloatingStackViewState();
}
class _FloatingStackViewState extends State<_FloatingStackView> {
  List<Widget> views = [];

  @override
  Widget build(BuildContext context) {
    final stack = Stack(
      children: views,
    );
    return stack;
  }

  void addLayer(Widget _w) {
    setState(() {
      views.add(_w);
    });
  }
  void clearLayer() {
    setState(() {
      views.clear();
    });
  }
  void removeLayer(Widget _w) {
    setState(() {
      views.remove(_w);
    });
  }
}

class _FloatingToastView extends StatefulWidget {
  const _FloatingToastView({
    super.key,
  });

  @override
  State<StatefulWidget> createState() => _FloatingToastViewState();
}
class _FloatingToastViewState extends State<_FloatingToastView> with TickerProviderStateMixin {
  List<Widget> toasts = [];

  @override
  Widget build(BuildContext context) {
    final stack = Column(
      children: [
        Expanded(child: Container(),),
        ...toasts,
      ],
    );
    return stack;
  }

  void addToast(String content) {
    if(toasts.length >= 3) return; // Add toast failed

    /// 1. animation1 size in
    /// 2. wait for 2 seconds
    /// 3. animation2 fade out
    /// 4. delete toast
    final toast = Container(
      margin: const EdgeInsets.fromLTRB(0, 4.0, 0, 4.0),
      width: double.infinity,
      child: Row(
        children: [
          Expanded(child: Container()),
          Container(
            padding: const EdgeInsets.all(8.0),
            constraints: const BoxConstraints.tightFor(width: 100),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4.0)),
            alignment: Alignment.center,
            child: Text(content, style: const TextStyle(color: Colors.white),),
          ),
          Expanded(child: Container()),
        ],
      ),
    );
    final _animation1 = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    final _animated1 = AnimatedBuilder(
      animation: _animation1,
      builder: (BuildContext context, child) {
        return SizeTransition(
          sizeFactor: _animation1,
          child: child,
        );
      },
      child: toast,
    );
    final _animation2 = AnimationController(vsync: this, duration: const Duration(milliseconds: 500), lowerBound: 0.0, upperBound: 1.0, value: 1.0);
    final _animated2 = AnimatedBuilder(
      animation: _animation2,
      builder: (BuildContext context, child) {
        return FadeTransition(
          opacity: _animation2,
          child: child,
        );
      },
      child: _animated1,
    );
    _animation1.addStatusListener((status) {
      if(status == AnimationStatus.completed) {
        final _ = Timer(const Duration(milliseconds: 2000), () {
          _animation2.reverse();
        });
      }
    });
    _animation2.addStatusListener((status) {
      if(status == AnimationStatus.dismissed) {
        setState(() {
          toasts.remove(_animated2);
        });
      }
    });
    setState(() {
      toasts.add(_animated2);
      _animation1.forward();
    });
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