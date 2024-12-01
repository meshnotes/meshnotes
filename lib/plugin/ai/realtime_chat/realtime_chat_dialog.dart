import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mesh_note/plugin/plugin_api.dart';
import 'ai_tools_manager.dart';
import 'audio_visualizer_widget.dart';
import 'chat_messages.dart';
import 'realtime_proxy.dart';
import 'subtitles.dart';

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
  static const double dialogWidth = 400; // fixed width and height of dialog
  static const double dialogHeight = 100;
  static const double paddingToScreenEdge = 5;
  late RealtimeProxy realtime;
  bool _isMuted = false;
  final visualizerKey = GlobalKey<AudioVisualizerWidgetState>();
  final subtitlesKey = GlobalKey<SubtitlesState>();
  double _xPosition = -1;
  double _yPosition = -1;
  bool _isLoading = false;
  bool _isError = false;
  late AiToolsManager _toolsManager;

  @override
  void initState() {
    super.initState();
    _isLoading = true;
    _isError = false;
    _toolsManager = AiToolsManager(pluginProxy: widget.proxy);
    final userNotes = widget.proxy.getUserNotes();
    realtime = RealtimeProxy(
      apiKey: widget.apiKey,
      userNotes: userNotes,
      tools: _toolsManager.buildTools(),
      showToastCallback: (error) {
        widget.proxy.showToast(error);
      },
      onErrorShutdown: () {
        widget.closeCallback?.call();
      },
      startVisualizerAnimation: _startVisualizerAnimation,
      stopVisualizerAnimation: _stopVisualizerAnimation,
      onChatMessagesUpdated: _onChatMessagesUpdated,
    );
    realtime.connect().then((value) {
      if(value) {
        setState(() {
          _isLoading = false;
          _isError = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _isError = true;
        });
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    realtime.shutdown();
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
      child: Row(
        children: [
          Expanded(
            child: Subtitles(
              key: subtitlesKey,
              messages: realtime.chatMessages,
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Align(
                alignment: Alignment.topLeft,
                child: _isError 
                  ? const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 24,
                    )
                  : (_isLoading 
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
                          ),
                        )
                      : AudioVisualizerWidget(
                          key: visualizerKey,
                          isPlaying: false,
                          color: const Color(0xFF2196F3),
                        )
                    ),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.bottomLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_isMuted ? Icons.mic_off : Icons.mic, 
                        color: _isMuted? Colors.red : null),
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
        ],
      ),
    );

    final gesture = GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          final newX = _xPosition + details.delta.dx;
          final newY = _yPosition + details.delta.dy;
          
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
    );
    final positioned = Positioned(
      left: _xPosition,
      top: _yPosition,
      child: gesture,
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

  void _onChatMessagesUpdated(ChatMessages messages) {
    subtitlesKey.currentState?.updateMessages(messages);
  }
}