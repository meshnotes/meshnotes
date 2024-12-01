import 'dart:math';
import 'package:flutter/material.dart';

class AudioVisualizerWidget extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  final double barWidth;
  final double spacing;
  
  const AudioVisualizerWidget({
    super.key,
    this.isPlaying = true,
    this.color = const Color(0xFF2196F3),
    this.barWidth = 8,
    this.spacing = 4,
  });

  @override
  State<AudioVisualizerWidget> createState() => AudioVisualizerWidgetState();
}

class AudioVisualizerWidgetState extends State<AudioVisualizerWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _barHeights = List.generate(5, (index) => 10 + Random().nextDouble() * 40);
  final List<Duration> _barDurations = List.generate(
    5,
    (index) => Duration(milliseconds: 400 + Random().nextInt(400)),
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    if (widget.isPlaying) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(AudioVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void pauseAnimation() {
    _controller.stop();
  }

  void playAnimation() {
    if(!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(
            5,
            (index) {
              final sinValue = sin(
                (_controller.value * 2 * pi) * (_barDurations[0].inMilliseconds / _barDurations[index].inMilliseconds)
              );
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.spacing),
                child: Container(
                  width: widget.barWidth,
                  height: _barHeights[index] * (0.3 + 0.7 * sinValue.abs()),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(widget.barWidth / 2),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
} 