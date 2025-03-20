import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mesh_note/plugin/plugin_api.dart';
import 'package:my_log/my_log.dart';
import 'package:permission_handler/permission_handler.dart';
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
  static const double defaultDialogWidth = 400; // fixed width and height of dialog
  static const double defaultDialogHeight = 100;
  static const double paddingToScreenEdge = 5;
  late RealtimeProxy realtime;
  bool _isMuted = false;
  final visualizerKey = GlobalKey<AudioVisualizerWidgetState>();
  final subtitlesKey = GlobalKey<SubtitlesState>();
  final aecAudioWebViewKey = GlobalKey();
  double _xPosition = -1;
  double _yPosition = -1;
  bool _isLoading = false;
  bool _isError = false;
  late AiToolsManager _toolsManager;
  late Future<bool> permissionFuture;

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
      onStateChanged: (state) {
        if(!mounted) return;
        if(state == RealtimeConnectionState.connected) {
          setState(() {
            _isLoading = false;
          });
        } else if(state == RealtimeConnectionState.connecting) {
          setState(() {
            _isLoading = true;
          });
        } else if(state == RealtimeConnectionState.error) {
          setState(() {
            _isLoading = false;
            _isError = true;
          });
        }
      },
      startVisualizerAnimation: _startVisualizerAnimation,
      stopVisualizerAnimation: _stopVisualizerAnimation,
      onChatMessagesUpdated: _onChatMessagesUpdated,
      playPopSoundAfterConnected: !widget.proxy.getPlatform().isIOS(), // Will failed to chat on iOS, I don't know why
    );
    permissionFuture = _startRealtimeChat();
  }

  @override
  void dispose() {
    super.dispose();
    realtime.shutdown();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height - 30;
    final dialogWidth = min(defaultDialogWidth, screenWidth - paddingToScreenEdge * 2);
    final dialogHeight = min(defaultDialogHeight, screenHeight - paddingToScreenEdge * 2);
    if(_xPosition < 0 || _yPosition < 0) {
      _xPosition = screenWidth.clamp(paddingToScreenEdge, screenWidth - dialogWidth - paddingToScreenEdge);
      _yPosition = screenHeight.clamp(paddingToScreenEdge, screenHeight - dialogHeight - paddingToScreenEdge);
    }
    final loadingWidget = _buildLoadingWidget();
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
              proxy: widget.proxy,
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Align(
                alignment: Alignment.topLeft,
                child: loadingWidget,
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
                          if(_isMuted) {
                            realtime.mute();
                          } else {
                            realtime.unmute();
                          }
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

  Widget _buildLoadingWidget() {
    String? fontFamily;
    if(widget.proxy.getPlatform().isWindows()) {
      fontFamily = 'Yuanti SC';
    }
    final futureBuilder = FutureBuilder<bool>(
      future: permissionFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Permission request not completed
          return const Center(
            child: CircularProgressIndicator(),
          );
        } else if (snapshot.hasData && snapshot.data == true) {
          // Permission request success
          if(_isError) {
            return const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 24,
            );
          } else {
            if(_isLoading) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2196F3)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Loading...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black,
                      fontStyle: FontStyle.normal,
                      decoration: TextDecoration.none,
                      fontWeight: FontWeight.normal,
                      fontFamily: fontFamily,
                    ),
                  ),
                ],
              );
            } else {
              MyLogger.info('build audio visualizer');
              final audioVisualizer = AudioVisualizerWidget(
                key: visualizerKey,
                isPlaying: false,
                color: const Color(0xFF2196F3),
              );
              return Column(
                children: [
                  audioVisualizer,
                ],
              );
            }
          }
        } else {
          // Permission request failed
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 24,
                ),
                const SizedBox(height: 8),
                Text(
                  'Permission denied',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                    fontStyle: FontStyle.normal,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.normal,
                    fontFamily: fontFamily,
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
    return futureBuilder;
  }

  Future<bool> requestPermissions() async {
    if(widget.proxy.getPlatform().isMobile()) {
      final statusMicrophone = await Permission.microphone.request();
      // final statusAudio = await Permission.audio.request();
      MyLogger.info('statusMicrophone: $statusMicrophone');
      if(statusMicrophone != PermissionStatus.granted) {
        return false;
      }
    }
    return true;
  }
  Future<bool> _startRealtimeChat() async {
    final granted = requestPermissions();
    granted.then((granted) {
      if(granted) {
        realtime.connect().then((connected) {
          if(connected) {
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
      } else {
        setState(() {
          _isLoading = false;
          _isError = true;
        });
      }
    });
    return granted;
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
