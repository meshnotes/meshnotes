import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mesh_note/plugin/plugin_api.dart';
import 'package:my_log/my_log.dart';
import 'audio_visualizer_widget.dart';
import 'realtime_proxy.dart';

class RealtimeChatDialog extends StatefulWidget {
  final void Function()? closeCallback;
  final String apiKey;
  final PluginProxy proxy;
  
  const RealtimeChatDialog({
    super.key,
    this.closeCallback,
    required this.apiKey,
    required this.proxy,
  });

  @override
  State<StatefulWidget> createState() => RealtimeChatDialogState();
}

class RealtimeChatDialogState extends State<RealtimeChatDialog> {
  static const double dialogWidth = 100; // fixed width and height of dialog
  static const double dialogHeight = 100;
  static const double paddingToScreenEdge = 5;
  late RealtimeProxy proxy;
  bool _isMuted = false;
  final visualizerKey = GlobalKey<AudioVisualizerWidgetState>();
  double _xPosition = -1;
  double _yPosition = -1;

  @override
  void initState() {
    super.initState();
    proxy = RealtimeProxy(
      apiKey: widget.apiKey,
      showToastCallback: (error) {
        widget.proxy.showToast(error);
      },
      onErrorShutdown: () {
        widget.closeCallback?.call();
      },
      startVisualizerAnimation: _startVisualizerAnimation,
      stopVisualizerAnimation: _stopVisualizerAnimation,
    );
    proxy.connect();
  }

  @override
  void dispose() {
    super.dispose();
    proxy.shutdown();
  }

  @override
  Widget build(BuildContext context) {
    if(_xPosition < 0 || _yPosition < 0) {
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height - 30;
      _xPosition = screenWidth.clamp(paddingToScreenEdge, screenWidth - dialogWidth - paddingToScreenEdge);
      _yPosition = screenHeight.clamp(paddingToScreenEdge, screenHeight - dialogHeight - paddingToScreenEdge);
    }
    final container = Container(
      width: dialogWidth,
      height: dialogHeight,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5).withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        // alignment: Alignment.center,
        children: [
          const Spacer(),
          AudioVisualizerWidget(
            key: visualizerKey,
            isPlaying: false, // Don't play animation before connected
            color: const Color(0xFF2196F3),
          ),
          Align(
            alignment: Alignment.bottomLeft,
              child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: _isMuted? Colors.red : null),
                  color: _isMuted ? Colors.red : null,
                  onPressed: () {
                    setState(() {
                      _isMuted = !_isMuted;
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.stop, color: Colors.black),
                  onPressed: _onClose,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final positioned = Positioned(
      left: _xPosition,
      top: _yPosition,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            final newX = details.globalPosition.dx;
            final newY = details.globalPosition.dy;
            
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;
            
            _xPosition = newX.clamp(paddingToScreenEdge, screenWidth - dialogWidth - paddingToScreenEdge);
            _yPosition = newY.clamp(paddingToScreenEdge, screenHeight - dialogHeight - paddingToScreenEdge);

            final distanceToTop = _yPosition;
            final distanceToBottom = screenHeight - (_yPosition + dialogHeight);
            final distanceToLeft = _xPosition;
            final distanceToRight = screenWidth - (_xPosition + dialogWidth);
            final minimalDistance = min(distanceToTop, min(distanceToBottom, min(distanceToLeft, distanceToRight)));

            // Snap to the edge with the minimal distance
            if(distanceToTop == minimalDistance) { // Snap to top
              _yPosition = paddingToScreenEdge;
            } else if(distanceToBottom == minimalDistance) { // Snap to bottom
              _yPosition = screenHeight - dialogHeight - paddingToScreenEdge;
            } else if(distanceToLeft == minimalDistance) { // Snap to left
              _xPosition = paddingToScreenEdge;
            } else { // Snap to right
              _xPosition = screenWidth - dialogWidth - paddingToScreenEdge;
            }
          });
        },
        child: container,
      ),
    );

    return positioned;
  }

  void _onClose() {
    widget.closeCallback?.call();
  }

  void _startVisualizerAnimation() {
    visualizerKey.currentState?.playAnimation();
  }

  void _stopVisualizerAnimation() {
    visualizerKey.currentState?.pauseAnimation();
  }
}