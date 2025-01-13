import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:mesh_note/plugin/user_notes_for_plugin.dart';
import 'package:my_log/my_log.dart';
import 'audio_player_proxy.dart';
import 'audio_recorder_proxy.dart';
import 'function_call.dart';
import 'realtime_api.dart';
import 'chat_messages.dart';

enum RealtimeConnectionState {
  idle,
  connecting,
  connected,
  error,
  shuttingDown,
}

class RealtimeProxy {
  final String apiKey;
  late RealtimeApi client;
  late AudioPlayerProxy audioPlayerProxy;
  late AudioRecorderProxy audioRecorderProxy;
  String? _popSoundAudioBase64;
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
  final bool usingNativeAudio;

  RealtimeProxy({
    required this.apiKey,
    required this.usingNativeAudio,
    this.userNotes,
    this.tools,
    this.showToastCallback,
    this.onErrorShutdown,
    this.startVisualizerAnimation,
    this.stopVisualizerAnimation,
    this.onChatMessagesUpdated,
    this.onStateChanged,
  });

  /// 1. Connect to Realtime API
  /// 2. Open record
  /// 3. Open audio player
  Future<bool> connect() async {
    if(_state != RealtimeConnectionState.idle) {
      return false;
    }
    _state = RealtimeConnectionState.connecting;
    if(usingNativeAudio) {
      await _openNativeRecorder();
      _openNativeAudioPlayer();
    }
    client = RealtimeApi(
      apiKey: apiKey,
      toolsDescription: tools?.getDescription(),
      onAiAudioDelta: _onAudioDelta,
      onInterrupt: _onInterrupt,
      onAiTranscriptDelta: _onAiTranscriptDelta,
      onAiTranscriptDone: _onAiTranscriptDone,
      onUserTranscriptDone: _onUserTranscriptDone,
      onWsError: _onWsError,
      onWsClose: _onWsClose,
      onFunctionCall: _onFunctionCall,
    );
    // Connect to Realtime API
    bool connected = false;
    if(chatMessages.isEmpty()) {
      connected = await client.connect(userContents: _buildUserContents());
    } else {
      connected = await client.connect(userContents: _buildUserContents(), history: _buildHistory());
    }
    if(connected) {
      MyLogger.info('Connected to Realtime API');
      _state = RealtimeConnectionState.connected;
      onStateChanged?.call(_state);
    }
    if(_popSoundAudioBase64 != null) { // Play a pop sound when connected
      MyLogger.debug('Play pop sound, $_popSoundAudioBase64');
      // Timer(const Duration(milliseconds: 1000), () {
      //   audioPlayerProxy.play(_popSoundAudioBase64!, 'pop_sound', 0);
      // });
      await Future.delayed(const Duration(milliseconds: 1000)); // Had to wait for 1s, or no sound on Android. I don't know why.
      audioPlayerProxy.play(_popSoundAudioBase64!, 'pop_sound', 0);
    }
    return connected;
  }

  void setAudioProxies(AudioPlayerProxy player, AudioRecorderProxy recorder) {
    audioPlayerProxy = player;
    audioRecorderProxy = recorder;
    recorder.setOnAudioData(appendInputAudio);
  }

  void appendInputAudio(String base64Data) {
    client.appendInputAudio(base64Data);
  }

  void shutdown() {
    if(_state != RealtimeConnectionState.connected) {
      return;
    }
    _state = RealtimeConnectionState.shuttingDown;
    shouldStop = true;
    client.shutdown();
    audioPlayerProxy.shutdown();
    audioRecorderProxy.stop();
    _animationTimer?.cancel();
    _state = RealtimeConnectionState.idle;
    onStateChanged?.call(_state);
  }

  void setPopSoundAudioBase64(String base64) {
    _popSoundAudioBase64 = base64;
  }

  Future<void> _openNativeRecorder() async {
    audioRecorderProxy = NativeAudioRecorderProxy(
      sampleRate: sampleRate,
      numChannels: numChannels,
    );
    audioRecorderProxy.setOnAudioData(appendInputAudio);
    audioRecorderProxy.start();
  }
  void _openNativeAudioPlayer() {
    audioPlayerProxy = NativeAudioPlayerProxyImpl(onPlaying: _onAudioActive); // play animation when playing audio
  }

  void _onAudioDelta(String base64Data, String itemId, int contentIndex) {
    audioPlayerProxy.play(base64Data, itemId, contentIndex);
  }

  void _onInterrupt() {
    MyLogger.info('Interrupted');
    final truncateInfo = audioPlayerProxy.stop();
    if(truncateInfo != null) {
      MyLogger.info('Interrupt, truncate info: ${truncateInfo.itemId} ${truncateInfo.contentIndex} ${truncateInfo.audioEndMs}');
      client.truncate(truncateInfo);
    }
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

  void _onWsError(Object error, StackTrace stackTrace) {
    _state = RealtimeConnectionState.error;
    onStateChanged?.call(_state);
    _tryToReconnect();
  }

  void _onWsClose() {
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
    bool connected = await client.connect(userContents: _buildUserContents(), history: _buildHistory());
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

  bool _isNotSilent(Uint8List data) {
    int sum = 0;
    for(final byte in data) {
      sum += byte;
    }
    double avg = sum / data.length;
    return avg > 10.0;
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
      client.sendFunctionResult(callId, jsonEncode(result));
      if(result.shouldInformUser) {
        client.informUserToolResult(callId);
      }
    }
  }
}