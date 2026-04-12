import 'package:flutter/material.dart';

class DragDropDashedBorderBox extends StatelessWidget {
  final Widget child;
  final Color color;
  final Color backgroundColor;
  final double borderRadius;

  const DragDropDashedBorderBox({
    super.key,
    required this.child,
    required this.color,
    required this.backgroundColor,
    this.borderRadius = 0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DragDropDashedBorderPainter(
        color: color,
        borderRadius: borderRadius,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: child,
      ),
    );
  }
}

class _DragDropDashedBorderPainter extends CustomPainter {
  final Color color;
  final double borderRadius;

  const _DragDropDashedBorderPainter({
    required this.color,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(borderRadius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for(final metric in path.computeMetrics()) {
      double distance = 0;
      const dashWidth = 6.0;
      const dashGap = 4.0;
      while(distance < metric.length) {
        final next = distance + dashWidth < metric.length ? distance + dashWidth : metric.length;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DragDropDashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.borderRadius != borderRadius;
  }
}
