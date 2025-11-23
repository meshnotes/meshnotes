import 'package:flutter/material.dart';

/// Custom circular progress widget with percentage display in the center.
class SyncProgressWidget extends StatelessWidget {
  final int progress; // 0-100
  final double size;

  const SyncProgressWidget({
    Key? key,
    required this.progress,
    this.size = 32.0,
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
          Text(
            '$progress%',
            style: TextStyle(
              fontSize: size * 0.25,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
