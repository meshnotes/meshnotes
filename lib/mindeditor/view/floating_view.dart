import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';

class FloatingViewManager {
  OverlayEntry? tipsEntry;

  void showBlockTips(BuildContext context, String content, LayerLink layerLink) {
    OverlayEntry tipsWidget = OverlayEntry(builder: (context) {
      return _TipsDialog(
        content: content,
        layerLink: layerLink,
        closeCallback: _closeBlockTips,
      );
    });
    tipsEntry = tipsWidget;
    Overlay.of(context).insert(tipsWidget);
  }

  void _closeBlockTips() {
    MyLogger.info('efantest: close block tips');
    tipsEntry?.remove();
    tipsEntry = null;
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