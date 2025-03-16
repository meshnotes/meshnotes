import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:mesh_note/plugin/user_notes_for_plugin.dart';
import 'package:mp_audio_stream/mp_audio_stream.dart';
import 'package:my_log/my_log.dart';
import 'function_call.dart';
import 'chat_messages.dart';
import 'realtime_api_webrtc.dart';

enum RealtimeConnectionState {
  idle,
  connecting,
  connected,
  error,
  shuttingDown,
}

class RealtimeProxy {
  AudioStream? _audioStream;
  final String apiKey;
  late RealtimeApiWebRtc clientWebRtc;
  final bool playPopSoundAfterConnected;
  bool shouldStop = false; // stop by user
  bool forceStop = false; // stop by too many errors
  // Just for chat history test
  // ChatMessages chatMessages = ChatMessages(messages: [
  //   ChatMessage(role: ChatRole.assistant, content: 'Hi, what can I help you with?'),
  //   ChatMessage(role: ChatRole.user, content: '我想聊一下关于三国演义的话题'),
  //   ChatMessage(role: ChatRole.assistant, content: '三国演义是中国古代四大名著之一，讲述了东汉末年到西晋初年的历史事件，主要围绕着蜀汉、曹魏、东吴三个势力之间的斗争。'),
  //   ChatMessage(role: ChatRole.user, content: '那你能给我讲讲三国演义的故事吗？'),
  //   ChatMessage(role: ChatRole.assistant, content: '当然可以，你想听哪个英雄的故事？'),
  //   ChatMessage(role: ChatRole.user, content: '我想听刘备的故事'),
  //   ChatMessage(role: ChatRole.assistant, content: '刘备是蜀汉的开国皇帝，他有着仁德和智谋，曾经在桃园三结义，与关羽、张飞一起立下誓言，共同为汉朝的复兴而努力。'),
  //   ChatMessage(role: ChatRole.user, content: '那他后来成功了吗？'),
  // ]);
  ChatMessages chatMessages = ChatMessages();
  UserNotes? userNotes;
  int errorRetryCount = 0;
  Function(String)? showToastCallback;
  Function()? onErrorShutdown;
  Function(RealtimeConnectionState)? onStateChanged;
  Timer? resetRetryCountTimer;
  Function? startVisualizerAnimation;
  Function? stopVisualizerAnimation;
  Timer? _animationTimer;
  RealtimeConnectionState _state = RealtimeConnectionState.idle;
  Function(ChatMessages)? onChatMessagesUpdated;
  AiTools? tools;
  // ignore: constant_identifier_names
  static const int MAX_ERROR_RETRY_COUNT = 3;
  static const int sampleRate = 24000;
  static const int numChannels = 1;
  static const int sampleSize = 16;

  RealtimeProxy({
    required this.apiKey,
    this.userNotes,
    this.tools,
    this.showToastCallback,
    this.onErrorShutdown,
    this.startVisualizerAnimation,
    this.stopVisualizerAnimation,
    this.onChatMessagesUpdated,
    this.onStateChanged,
    this.playPopSoundAfterConnected = true,
  });

  /// 1. Connect to Realtime API
  /// 2. Open record
  /// 3. Open audio player
  Future<bool> connect() async {
    if(_state != RealtimeConnectionState.idle) {
      return false;
    }
    _state = RealtimeConnectionState.connecting;
    bool connected = false;
    clientWebRtc = RealtimeApiWebRtc(
      apiKey: apiKey,
      toolsDescription: tools?.getDescription(),
      onAiTranscriptDelta: _onAiTranscriptDelta,
      onAiTranscriptDone: _onAiTranscriptDone,
      onUserTranscriptDone: _onUserTranscriptDone,
      onFailed: _onFailed,
      onClose: _onClose,
      onFunctionCall: _onFunctionCall,
    );
    if(chatMessages.isEmpty()) {
      connected = await clientWebRtc.connectWebRtc(userContents: _buildUserContents());
    } else {
      connected = await clientWebRtc.connectWebRtc(userContents: _buildUserContents(), history: _buildHistory());
    }
    if(connected) {
      MyLogger.info('Connected to Realtime API');
      _state = RealtimeConnectionState.connected;
      onStateChanged?.call(_state);
    }
    if(playPopSoundAfterConnected) { // Play a pop sound when connected
      await Future.delayed(const Duration(milliseconds: 800));
      _playPopSound('assets/sound/pop_sound_pcm24k.pcm');
    }
    return connected;
  }

  void mute() {
    clientWebRtc.toggleMute(true);
  }
  void unmute() {
    clientWebRtc.toggleMute(false);
  }

  void shutdown() {
    if(_state != RealtimeConnectionState.connected) {
      return;
    }
    _state = RealtimeConnectionState.shuttingDown;
    shouldStop = true;
    clientWebRtc.shutdown();
    _animationTimer?.cancel();
    _state = RealtimeConnectionState.idle;
    _audioStream?.uninit();
    _audioStream = null;
    onStateChanged?.call(_state);
  }

  void _onAiTranscriptDelta(String text) {
    MyLogger.debug('AI transcript delta: $text');
    chatMessages.updateAiTranscriptDelta(text);
    onChatMessagesUpdated?.call(chatMessages);
  }

  void _onAiTranscriptDone(String text) {
    MyLogger.debug('AI transcript done: $text');
    chatMessages.updateAiTranscriptDone(text);
    onChatMessagesUpdated?.call(chatMessages);
  }

  void _onUserTranscriptDone(String text) {
    MyLogger.debug('User transcript done: $text');
    chatMessages.updateUserTranscriptDone(text);
    onChatMessagesUpdated?.call(chatMessages);
  }

  String? _buildUserContents() {
    if(userNotes == null) {
      return null;
    }
    final content = userNotes!.getNotesContent();
    String prompt = 'Here is the user\'s content. Refer to this only if user asks about it. Be caution, user doesn\'t care the id, only care the content. so it\'s not necessary to mention the id in your response.';
    return prompt + '\n' + content;
  }
  String? _buildHistory() {
    if(chatMessages.isEmpty()) {
      return null;
    }
    final messageHistory = chatMessages.buildHistory();
    String prompt = 'Please continue the conversation, here is the previous chatting history(${ChatRole.user} means user, ${ChatRole.assistant} means you):';
    return prompt + '\n' + messageHistory;
  }

  void _onFailed() {
    _state = RealtimeConnectionState.error;
    onStateChanged?.call(_state);
    _tryToReconnect();
  }

  void _onClose() {
    _state = RealtimeConnectionState.error;
    onStateChanged?.call(_state);
    _tryToReconnect();
  }
  Future<void> _tryToReconnect() async {
    if(shouldStop) {
      return;
    }
    if(errorRetryCount >= MAX_ERROR_RETRY_COUNT) {
      _state = RealtimeConnectionState.shuttingDown;
      forceStop = true;
      showToastCallback?.call('Realtime API failed too many times');
      onErrorShutdown?.call();
      _state = RealtimeConnectionState.idle;
      return;
    }
    errorRetryCount++;
    MyLogger.info('Reconnecting for the $errorRetryCount-th time...');
    _state = RealtimeConnectionState.connecting;
    onStateChanged?.call(_state);
    bool connected = await clientWebRtc.connectWebRtc(userContents: _buildUserContents(), history: _buildHistory());
    if(connected) {
      // After connected, reset the retry count if it's stable running for 10 seconds
      resetRetryCountTimer?.cancel();
      resetRetryCountTimer = Timer(const Duration(seconds: 10), () {
        errorRetryCount = 0;
      });
    }
    _state = RealtimeConnectionState.connected;
    onStateChanged?.call(_state);
  }

  void _onAudioActive(int duration) {
    _cancelAnimationTimer();
    startVisualizerAnimation?.call();
    if(stopVisualizerAnimation != null) {
      _startAnimationTimer(duration);
    }
  }
  void _cancelAnimationTimer() {
    _animationTimer?.cancel();
  }
  void _startAnimationTimer(int duration) {
    _cancelAnimationTimer();
    _animationTimer = Timer(Duration(milliseconds: duration), () {
      stopVisualizerAnimation?.call();
    });
  }

  Future<void> _onFunctionCall(String callId, String name, String arguments) async {
    MyLogger.info('Function call: $callId $name $arguments');
    final result = tools?.invokeFunction(name, arguments);
    if(result == null) {
      MyLogger.warn('Function not found: name=$name');
    } else {
      clientWebRtc.sendFunctionResult(callId, jsonEncode(result));
      if(result.shouldInformUser) {
        clientWebRtc.informUserToolResult(callId);
      }
    }
  }

  _playPopSound(String assetPath) async {
    if(_audioStream == null) {
      _audioStream = getAudioStream();
      _audioStream!.init(channels: 2, sampleRate: 24000);
    }
    final data = await rootBundle.load(assetPath);
    final len = data.lengthInBytes ~/ 2;
    Float32List floatData = Float32List(len * 2);
    for (int i = 0; i < len; i++) {
      final pcm16 = data.getInt16(i * 2, Endian.little);
      floatData[i * 2] = pcm16 / 32768.0; // Normalize to [-1.0, 1.0]
      floatData[i * 2 + 1] = floatData[i * 2]; // Make it double channels
    }
    _audioStream!.push(floatData);
  }
}