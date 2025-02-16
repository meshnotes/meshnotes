import 'package:flutter/material.dart';
import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';

typedef OnWidgetSizeChange = void Function(Size size);

class MeasureSize extends StatefulWidget {
  final Widget child;
  final OnWidgetSizeChange onChange;

  const MeasureSize({
    Key? key,
    required this.onChange,
    required this.child,
  }) : super(key: key);

  @override
  State<MeasureSize> createState() => _MeasureSizeState();
}

class _MeasureSizeState extends State<MeasureSize> {
  Size? _oldSize;

  @override
  Widget build(BuildContext context) {
    Util.runInPostFrame(() => _notifySize());
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (notification) {
        Util.runInPostFrame(() => _notifySize());
        return true;
      },
      child: SizeChangedLayoutNotifier(
        child: widget.child,
      ),
    );
  }

  void _notifySize() {
    final size = context.size;
    if (_oldSize != size && size != null) {
      _oldSize = size;
      MyLogger.info('size changed: $size');
      widget.onChange(size);
    }
  }
} 