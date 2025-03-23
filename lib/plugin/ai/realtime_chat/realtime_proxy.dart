import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:mesh_note/plugin/ai/realtime_chat/native_ws_implement/native_ws_api.dart';
import 'package:mesh_note/plugin/ai/realtime_chat/webview_ws_implement/webview_ws_api.dart';
import 'package:mesh_note/plugin/user_notes_for_plugin.dart';
import 'package:my_log/my_log.dart';
import 'function_call.dart';
import 'chat_messages.dart';
import 'realtime_api.dart';
import 'realtime_prompts.dart';

enum RealtimeConnectionState {
  idle,
  connecting,
  connected,
  ready,
  error,
  shuttingDown,
}

enum RealtimeChoise {
  nativeWebSocketImplementation,
  webViewWebSocketImplementation,
  webViewWebRtcImplementation,
}

class RealtimeProxy {
  final String apiKey;
  late RealtimeApi client;
  final bool playPopSoundAfterConnected;
  bool shouldStop = false; // stop by user
  bool forceStop = false; // stop by too many errors
  final RealtimeChoise implementationChoice;
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
  final String popSoundAudioBase64;
  final UserNotes? Function() getUserNotes;

  RealtimeProxy({
    required this.apiKey,
    required this.implementationChoice,
    this.tools,
    this.showToastCallback,
    this.onErrorShutdown,
    this.startVisualizerAnimation,
    this.stopVisualizerAnimation,
    this.onChatMessagesUpdated,
    this.onStateChanged,
    this.playPopSoundAfterConnected = true,
    required this.popSoundAudioBase64,
    required this.getUserNotes,
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
    client = _createRealtimeApiImplementation();
    connected = await client.connect();
    if(connected) {
      MyLogger.info('RealtimeProxy: Connected to Realtime API');
      _state = RealtimeConnectionState.connected;
      onStateChanged?.call(_state);
    }
    return connected;
  }

  Widget? buildWebview() {
    return client.buildWebview();
  }

  void mute() {
    client.toggleMute(true);
  }
  void unmute() {
    client.toggleMute(false);
  }

  void dispose() {
    if(_state == RealtimeConnectionState.shuttingDown || _state == RealtimeConnectionState.idle) {
      MyLogger.warn('RealtimeProxy: duplicate shutdown');
      return;
    }
    MyLogger.info('RealtimeProxy: now try to shutdown');
    _state = RealtimeConnectionState.shuttingDown;
    shouldStop = true;
    client.shutdown();
    _animationTimer?.cancel();
    _state = RealtimeConnectionState.idle;
  }

  RealtimeApi _createRealtimeApiImplementation() {
    final eventHandler = RealtimeEventHandler(
      onData: _onData,
      onError: (String error) {
        _onFailed();
      },
      onClose: _onClose,
      onPlaying: _onAudioActive,
    );
    switch(implementationChoice) {
      case RealtimeChoise.nativeWebSocketImplementation:
        return _createNativeWebSocketImplementation(eventHandler);
      case RealtimeChoise.webViewWebSocketImplementation:
        return _createWebViewWebSocketImplementation(eventHandler);
      case RealtimeChoise.webViewWebRtcImplementation:
        return _createWebViewWebRtcImplementation(eventHandler);
    }
  }
  RealtimeApi _createNativeWebSocketImplementation(RealtimeEventHandler eventHandler) {
    return RealtimeNativeWsApi(
      sampleRate: sampleRate,
      numChannels: numChannels,
      sampleSize: sampleSize,
      apiKey: apiKey,
      toolsDescription: tools?.getDescription(),
      eventHandler: eventHandler,
    );
  }
  RealtimeApi _createWebViewWebSocketImplementation(RealtimeEventHandler eventHandler) {
    return RealtimeWebviewWsApi(
      apiKey: apiKey,
      sampleRate: sampleRate,
      numChannels: numChannels,
      sampleSize: sampleSize,
      eventHandler: eventHandler,
    );
  }
  RealtimeApi _createWebViewWebRtcImplementation(RealtimeEventHandler eventHandler) {
    return RealtimeWebviewWsApi(
      apiKey: apiKey,
      sampleRate: sampleRate,
      numChannels: numChannels,
      sampleSize: sampleSize,
      eventHandler: eventHandler,
    );
  }
  void _onAiTranscriptDelta(String text) {
    MyLogger.debug('RealtimeProxy: AI transcript delta: $text');
    chatMessages.updateAiTranscriptDelta(text);
    onChatMessagesUpdated?.call(chatMessages);
  }

  void _onAiTranscriptDone(String text) {
    MyLogger.debug('RealtimeProxy: AI transcript done: $text');
    chatMessages.updateAiTranscriptDone(text);
    onChatMessagesUpdated?.call(chatMessages);
  }

  void _onUserTranscriptDone(String text) {
    MyLogger.debug('RealtimeProxy: User transcript done: $text');
    chatMessages.updateUserTranscriptDone(text);
    onChatMessagesUpdated?.call(chatMessages);
  }

  String? _buildUserContents() {
    final userNotes = getUserNotes();
    if(userNotes == null) {
      return null;
    }
    final content = userNotes.getNotesContent();
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
  void _onData(Map<String, dynamic> json) {
    String type = json['type']!;
    String? eventId = json['event_id'];
    String? itemId = json['item_id'];
    if(type.startsWith('response.')) {
      _onResponse(type, eventId, itemId, json);
    } else if(type.startsWith('input')) {
      _onInput(type, eventId, itemId, json);
    } else if(type.startsWith('conversation.')) {
      _onConversation(type, eventId, itemId, json);
    } else if(type.startsWith('session')) {
      _onSession(type, eventId, itemId, json);
    } else if(type == 'error') {
      final errorBody = json['error'];
      final errorType = errorBody['type'];
      final errorCode = errorBody['code'];
      final errorMessage = errorBody['message'];
      _onApplicationError(errorType, errorCode, errorMessage);
    } else {
      MyLogger.info('Native WebSocket Realtime API: $json');
    }
    // Other events
    // rate_limits.updated
  }
  /// response.created: with response id in json['response']['id']
  /// response.output_item.added: with item id in json['item']['id']
  /// response.audio.done: no any useful information
  /// response.audio_transcript.delta: json['delta'], delta transcript text
  /// response.audio_transcript.done: full audio transcript text
  /// response.output_item.done: audio transcript
  /// response.content_part.done: full audio transcript text
  /// response.done: audio transcript, with usage information
  /// *No response.audio.delta: json['delta'], audio base64 string, PCM16, mono channel, 24000 Hz, already handled by RealtimeApi implementation
  ///                           No this event for WebRtc implementation
  void _onResponse(String type, String? eventId, String? itemId, Map<String, dynamic> json) {
    // String? responseId = json['response_id'];
    if(type == 'response.audio_transcript.delta') {
      final text = json['delta'] as String;
      _onAiTranscriptDelta(text);
    } else if(type == 'response.audio_transcript.done') {
      final text = json['transcript'] as String;
      _onAiTranscriptDone(text);
    } else if(type == 'response.function_call_arguments.done') {
      final callId = json['call_id'] as String;
      final name = json['name'] as String;
      final arguments = json['arguments'] as String;
      _onFunctionCall(callId, name, arguments);
    } else {
      MyLogger.debug('RealtimeProxy onResponse: $json');
    }
  }
  /// input_audio_buffer.speech_started: Already handled by RealtimeApi implementation
  /// input_audio_buffer.speech_stopped
  /// input_audio_buffer.committed
  void _onInput(String type, String? eventId, String? itemId, Map<String, dynamic> json) {
    if(type == 'input_audio_buffer.speech_started') {
    } else if(type == 'input_audio_buffer.speech_stopped') {
      // onSpeechStopped();
    } else if(type == 'input_audio_buffer.committed') {
      // onAudioCommitted();
    }
  }
  /// conversation.item.created
  /// conversation.item.input_audio_transcription.completed: user audio transcript
  void _onConversation(String type, String? eventId, String? itemId, Map<String, dynamic> json) {
    MyLogger.debug('Native WebSocket Realtime API: $json');
    if(type == 'conversation.item.input_audio_transcription.completed') {
      final text = json['transcript'];
      _onUserTranscriptDone(text);
    }
  }
  void _onSession(String type, String? eventId, String? itemId, Map<String, dynamic> json) {
    if(type == 'session.created') { // Update session after created
      _onCreated();
    } else if(type == 'session.updated') {
      _onSessionUpdated();
      _state = RealtimeConnectionState.ready;
      onStateChanged?.call(_state);
    }
  }
  void _onCreated() {
    MyLogger.info('RealtimeProxy: Session created');
      _updateSession();
      _sendUserContents();
      _sendHistory();
  }
  void _sendUserContents() {
    final userContents = _buildUserContents();
    if(userContents == null) {
      return;
    }
    // client.sendEvent({'type': 'session.update', 'event_id': _generateEventId(), 'session': {'user_contents': userContents}});
  }
  void _sendHistory() {
    final history = _buildHistory();
    if(history == null) {
      return;
    }
    // client.sendEvent({'type': 'session.update', 'event_id': _generateEventId(), 'session': {'history': history}});
  }
  void _onSessionUpdated() {
    MyLogger.info('RealtimeProxy: Session updated');
    client.playAudio(popSoundAudioBase64);
  }
  void _onApplicationError(String? errorType, String? errorCode, String? errorMessage) {
    MyLogger.err('RealtimeProxy: receive error: type=$errorType, code=$errorCode, message=$errorMessage');
    // _onFailed();
  }


  Future<void> _tryToReconnect() async {
    if(shouldStop) {
      return;
    }
    if(errorRetryCount >= MAX_ERROR_RETRY_COUNT) {
      dispose();
      forceStop = true;
      showToastCallback?.call('RealtimeProxy: Failed too many times');
      onStateChanged?.call(_state);
      return;
    }
    errorRetryCount++;
    MyLogger.info('RealtimeProxy: Reconnecting for the $errorRetryCount-th time...');
    _state = RealtimeConnectionState.connecting;
    onStateChanged?.call(_state);
    bool connected = await client.connect();
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

  void _updateSession({Map<String, dynamic>? modifications}) {
    Map<String, dynamic> sessionObject = {
      'modalities': ['text', 'audio'],
      'instructions': RealtimePrompts.instructionsWithUserContent,
      'voice': 'alloy',
      'input_audio_format': 'pcm16',
      'output_audio_format': 'pcm16',
      'input_audio_transcription': {
        'model': 'whisper-1',
      },
      'turn_detection': {
        'type': 'server_vad',
        'threshold': 0.5,
        'prefix_padding_ms': 500,
        'silence_duration_ms': 200,
      },
      'tools': tools?.getDescription()?? [],
      'tool_choice': 'auto',
      'temperature': 0.8,
    };
    if(modifications != null) {
      sessionObject.addAll(modifications);
    }
    final updateSessionObject = {
      'type': 'session.update',
      'event_id': _generateEventId(),
      'session': sessionObject,
    };
    MyLogger.debug('RealtimeProxy: update session: $updateSessionObject');
    client.sendEvent(updateSessionObject);
  }

  String _generateEventId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
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
    MyLogger.info('RealtimeProxy: Function call: $callId $name $arguments');
    final result = tools?.invokeFunction(name, arguments);
    if(result == null) {
      MyLogger.warn('RealtimeProxy: Function not found: name=$name');
    } else {
      _sendFunctionResult(callId, jsonEncode(result));
      if(result.shouldInformUser) {
        _informUserToolResult(callId);
      }
    }
  }
  // Called when function call is done
  void _sendFunctionResult(String callId, String result) {
    final sendFunctionResultObject = {
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': callId,
        'output': result,
      },
    };
    client.sendEvent(sendFunctionResultObject);
  }
  // Called when the function call result need to be informed to user
  void _informUserToolResult(String callId) {
    _sendResponseCreate('please tell user about the tool result of call_id=$callId.');
  }
  void _sendResponseCreate(String text) {
    final responseCreateObject = {
      'type': 'response.create',
      'response': {
        'modalities': ['text', 'audio'],
        'instructions': text,
      },
    };
    client.sendEvent(responseCreateObject);
  }
}