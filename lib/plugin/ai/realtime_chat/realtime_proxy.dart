import 'dart:async';
import 'dart:typed_data';
import 'package:mesh_note/plugin/user_notes_for_plugin.dart';
import 'package:my_log/my_log.dart';
import 'package:record/record.dart';
import 'audio_player_proxy.dart';
import 'realtime_api.dart';
import 'chat_messages.dart';

enum _State {
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
  late AudioRecorder record;
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
  Timer? resetRetryCountTimer;
  Function? startVisualizerAnimation;
  Function? stopVisualizerAnimation;
  Timer? _animationTimer;
  _State _state = _State.idle;
  Function(ChatMessages)? onChatMessagesUpdated;

  // ignore: constant_identifier_names
  static const int MAX_ERROR_RETRY_COUNT = 3;

  RealtimeProxy({
    required this.apiKey,
    this.userNotes,
    this.showToastCallback,
    this.onErrorShutdown,
    this.startVisualizerAnimation,
    this.stopVisualizerAnimation,
    this.onChatMessagesUpdated,
  });

  /// 1. Connect to Realtime API
  /// 2. Open record
  /// 3. Open audio player
  Future<bool> connect() async {
    if(_state != _State.idle) {
      return false;
    }
    _state = _State.connecting;
    client = RealtimeApi(
      apiKey: apiKey,
      onAiAudioDelta: _onAudioDelta,
      onInterrupt: _onInterrupt,
      onAiTranscriptDelta: _onAiTranscriptDelta,
      onAiTranscriptDone: _onAiTranscriptDone,
      onUserTranscriptDone: _onUserTranscriptDone,
      onWsError: _onWsError,
      onWsClose: _onWsClose,
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
    }
    await _openRecord();
    audioPlayerProxy = AudioPlayerProxy(onPlaying: _onAudioActive); // play animation when playing audio
    if(connected) {
      _state = _State.connected;
    }
    return connected;
  }

  void appendInputAudio(Uint8List data) {
    client.appendInputAudio(data);
  }

  void shutdown() {
    if(_state != _State.connected) {
      return;
    }
    _state = _State.shuttingDown;
    shouldStop = true;
    client.shutdown();
    audioPlayerProxy.shutdown();
    record.stop();
    _animationTimer?.cancel();
    _state = _State.idle;
  }

  Future<void> _openRecord() async {
    record = AudioRecorder();
    if(await record.hasPermission()) {
      final stream = await record.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: 24000,
      ));
      stream.listen((data) {
        if(shouldStop || forceStop) {
          return;
        }
        // MyLogger.info('Voice chat: ${data.length} bytes');
        appendInputAudio(data);
        // if(_isNotSilent(data)) {
        //   MyLogger.info('Not silent, play animation');
        //   _onAudioActive(100); // play animation
        // }
        // audioPlayerProxy.play(data);
      });
    }
  }

  void _onAudioDelta(Uint8List data, String itemId, int contentIndex) {
    audioPlayerProxy.play(data, itemId, contentIndex);
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
    MyLogger.info('AI transcript delta: $text');
    chatMessages.updateAiTranscriptDelta(text);
    onChatMessagesUpdated?.call(chatMessages);
  }

  void _onAiTranscriptDone(String text) {
    MyLogger.info('AI transcript done: $text');
    chatMessages.updateAiTranscriptDone(text);
    onChatMessagesUpdated?.call(chatMessages);
  }

  void _onUserTranscriptDone(String text) {
    MyLogger.info('User transcript done: $text');
    chatMessages.updateUserTranscriptDone(text);
    onChatMessagesUpdated?.call(chatMessages);
  }

  String? _buildUserContents() {
    if(userNotes == null) {
      return null;
    }
    final content = userNotes!.getNotesContent();
    String prompt = 'Here is the user\'s content. Be caution, user doesn\'t care the id, only care the content. so it\'s not necessary to mention the id in your response.';
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
    _state = _State.error;
    _tryToReconnect();
  }

  void _onWsClose() {
    _state = _State.error;
    _tryToReconnect();
  }
  Future<void> _tryToReconnect() async {
    if(shouldStop) {
      return;
    }
    if(errorRetryCount >= MAX_ERROR_RETRY_COUNT) {
      _state = _State.shuttingDown;
      forceStop = true;
      showToastCallback?.call('Realtime API failed too many times');
      onErrorShutdown?.call();
      _state = _State.idle;
      return;
    }
    errorRetryCount++;
    MyLogger.info('Reconnecting for the $errorRetryCount-th time...');
    _state = _State.connecting;
    bool connected = await client.connect(userContents: _buildUserContents(), history: _buildHistory());
    if(connected) {
      // After connected, reset the retry count if it's stable running for 10 seconds
      resetRetryCountTimer?.cancel();
      resetRetryCountTimer = Timer(const Duration(seconds: 10), () {
        errorRetryCount = 0;
      });
    }
    _state = _State.connected;
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
}