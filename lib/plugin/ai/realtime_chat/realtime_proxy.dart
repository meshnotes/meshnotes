import 'dart:async';
import 'dart:typed_data';

import 'package:mesh_note/util/util.dart';
import 'package:my_log/my_log.dart';
import 'package:record/record.dart';
import 'audio_player_proxy.dart';
import 'realtime_api.dart';

enum ChatRole {
  user,
  assistant,
}
class ChatMessage {
  final ChatRole role;
  final String content;
  final bool isComposing;
  ChatMessage({required this.role, required this.content, this.isComposing = false});
}

class RealtimeProxy {
  final String apiKey;
  late RealtimeApi client;
  late AudioPlayerProxy audioPlayerProxy;
  late AudioRecorder record;
  bool shouldStop = false; // stop by user
  bool forceStop = false; // stop by too many errors
  List<ChatMessage> chatMessages = [];
  int errorRetryCount = 0;
  Function(String)? showToastCallback;
  Function()? onErrorShutdown;
  Timer? resetRetryCountTimer;
  Function? startVisualizerAnimation;
  Function? stopVisualizerAnimation;
  Timer? _animationTimer;

  // ignore: constant_identifier_names
  static const int MAX_ERROR_RETRY_COUNT = 3;

  RealtimeProxy({
    required this.apiKey,
    this.showToastCallback,
    this.onErrorShutdown,
    this.startVisualizerAnimation,
    this.stopVisualizerAnimation,
  });

  Future<bool> connect() async {
    // Just for a test
    // chatMessages = [
    //   ChatMessage(role: ChatRole.assistant, content: 'Hi, what can I help you with?'),
    //   ChatMessage(role: ChatRole.user, content: '我想聊一下关于三国演义的话题'),
    //   ChatMessage(role: ChatRole.assistant, content: '三国演义是中国古代四大名著之一，讲述了东汉末年到西晋初年的历史事件，主要围绕着蜀汉、曹魏、东吴三个势力之间的斗争。'),
    //   ChatMessage(role: ChatRole.user, content: '那你能给我讲讲三国演义的故事吗？'),
    //   ChatMessage(role: ChatRole.assistant, content: '当然可以，你想听哪个英雄的故事？'),
    //   ChatMessage(role: ChatRole.user, content: '我想听刘备的故事'),
    //   ChatMessage(role: ChatRole.assistant, content: '刘备是蜀汉的开国皇帝，他有着仁德和智谋，曾经在桃园三结义，与关羽、张飞一起立下誓言，共同为汉朝的复兴而努力。'),
    //   ChatMessage(role: ChatRole.user, content: '那他后来成功了吗？'),
    // ];
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
    // bool connected = await client.reconnect(history: _buildHistory());
    bool connected = await client.connect();
    if(connected) {
      MyLogger.info('Connected to Realtime API');
    }
    await _openRecord();
    audioPlayerProxy = AudioPlayerProxy(onPlaying: _onAudioActive); // play animation when playing audio
    return connected;
  }

  void appendInputAudio(Uint8List data) {
    client.appendInputAudio(data);
  }

  void shutdown() {
    shouldStop = true;
    client.shutdown();
    audioPlayerProxy.shutdown();
    record.stop();
    _animationTimer?.cancel();
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
        _onAudioActive(); // play animation
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

  ChatMessage? _popComposingMessage() {
    for(int i = chatMessages.length - 1; i >= 0; i--) {
      if(chatMessages[i].isComposing) {
        return chatMessages.removeAt(i);
      }
    }
    return null;
  }

  void _onAiTranscriptDelta(String text) {
    MyLogger.info('AI transcript delta: $text');
    final oldMessage = _popComposingMessage();
    if(oldMessage != null) {
      chatMessages.add(ChatMessage(role: ChatRole.assistant, content: oldMessage.content + text, isComposing: true));
    } else {
      chatMessages.add(ChatMessage(role: ChatRole.assistant, content: text, isComposing: true));
    }
  }

  void _onAiTranscriptDone(String text) {
    MyLogger.info('AI transcript done: $text');
    final _ = _popComposingMessage();
    chatMessages.add(ChatMessage(role: ChatRole.assistant, content: text));
  }

  void _onUserTranscriptDone(String text) {
    MyLogger.info('User transcript done: $text');
    chatMessages.add(ChatMessage(role: ChatRole.user, content: text));
  }

  String _buildHistory() {
    String messageList = chatMessages.map((e) => '${e.role}: ${e.content}').join('\n');
    String prompt = 'Please continue the conversation, here is the previous chatting history(${ChatRole.user} means user, ${ChatRole.assistant} means you):';
    return prompt + '\n' + messageList;
  }

  void _onWsError(Object error, StackTrace stackTrace) {
    _tryToReconnect();
  }

  void _onWsClose() {
    _tryToReconnect();
  }
  Future<void> _tryToReconnect() async {
    if(shouldStop) {
      return;
    }
    if(errorRetryCount >= MAX_ERROR_RETRY_COUNT) {
      forceStop = true;
      showToastCallback?.call('Realtime API failed too many times');
      onErrorShutdown?.call();
      return;
    }
    errorRetryCount++;
    MyLogger.info('Reconnecting for the $errorRetryCount-th time...');
    bool connected = await client.reconnect(history: _buildHistory());
    if(connected) {
      // After connected, reset the retry count if it's stable running for 10 seconds
      resetRetryCountTimer?.cancel();
      resetRetryCountTimer = Timer(const Duration(seconds: 10), () {
        errorRetryCount = 0;
      });
    }
  }

  void _onAudioActive() {
    startVisualizerAnimation?.call();
    if(stopVisualizerAnimation != null) {
      _startAnimationTimer();
    }
  }
  void _startAnimationTimer() {
    _animationTimer?.cancel();
    _animationTimer = Timer(const Duration(milliseconds: 100), () {
      stopVisualizerAnimation?.call();
    });
  }
}