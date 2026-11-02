import 'package:flutter/material.dart';
import '../tasks/event_tasks.dart';

/// Custom circular progress widget with percentage display in the center.
class SyncProgressWidget extends StatelessWidget {
  final int progress; // 0-100
  final double size;
  final SyncDirection direction;

  const SyncProgressWidget({
    Key? key,
    required this.progress,
    this.size = 32.0,
    this.direction = SyncDirection.download,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final progressValue = (progress / 100.0).clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progressValue,
              strokeWidth: 3.0,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.grey),
              backgroundColor: Colors.grey.withOpacity(0.2),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$progress%', style: TextStyle(fontSize: size * 0.25, fontWeight: FontWeight.w500, color: Colors.grey[700])),
              Icon(direction == SyncDirection.upload ? Icons.arrow_upward : Icons.arrow_downward, size: size * 0.32, color: Colors.grey[700]),
            ],
          ),
        ],
      ),
    );
  }
}
