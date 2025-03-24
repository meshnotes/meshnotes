/// Native WebSocket implementation
/// No AEC(Acoustic Echo Cancellation), so you need earphones
/// Currently only used in Linux mode. Because I didn't find a good way to implement webview in Linux
import 'dart:io';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:my_log/my_log.dart';

import '../realtime_api.dart';
import 'realtime_ws_helper.dart';
import 'audio_player_proxy.dart';
import 'audio_recorder_proxy.dart';

class RealtimeNativeWsApi extends RealtimeApi {
  late AudioRecorderProxy audioRecorderProxy;
  late AudioPlayerProxy audioPlayerProxy;
  final String url = 'wss://api.openai.com/v1/realtime';
  final String model = 'gpt-4o-realtime-preview-2024-10-01';
  final String apiKey;
  final List<Map<String, dynamic>>? toolsDescription;
  WebSocket? ws;
  final void Function(Object, StackTrace)? onWsError;
  final void Function()? onWsClose;

  // ignore: constant_identifier_names
  static const int MAX_RECONNECT_TIMES = 3;

  RealtimeNativeWsApi({
    required this.apiKey,
    required super.sampleRate,
    required super.numChannels,
    required super.sampleSize,
    this.toolsDescription,
    this.onWsError,
    this.onWsClose,
    required super.eventHandler,
  });

  @override
  Future<bool> connect() async {
    return await _connect();
  }

  @override
  void shutdown() {
    ws?.close();
    audioRecorderProxy.shutdown();
    audioPlayerProxy.shutdown();
  }

  @override
  void sendEvent(Map<String, dynamic> event) {
    ws!.add(jsonEncode(event));
  }
 
  @override
  void toggleMute(bool mute) {
    if(mute) {
      audioRecorderProxy.mute();
    } else {
      audioRecorderProxy.unmute();
    }
  }

  @override
  Widget? buildWebview() {
    return null;
  }

  @override
  void playAudio(String audioBase64) {
    audioPlayerProxy.play(audioBase64, '', 0, volume: 1.0);
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
    audioPlayerProxy = NativeAudioPlayerProxyImpl(onPlaying: eventHandler.onPlaying); // play animation when playing audio
  }
  Future<bool> _connect() async {
    await _openNativeRecorder();
    _openNativeAudioPlayer();
    for(int i = 0; i < MAX_RECONNECT_TIMES; i++) {
      if(i > 0) {
        MyLogger.info('Native WebSocket Realtime API: reconnecting for the $i-th time...');
      }
      try {
        ws = await WebSocket.connect(
          '$url?model=$model',
          headers: {
            'Authorization': 'Bearer $apiKey',
            'OpenAI-Beta': 'realtime=v1',
          },
        );
        ws!.listen(_onData, onError: _onError, onDone: _onClose);
        return true;
      } catch(e) {
        MyLogger.err('Native WebSocket Realtime API connect failed: $e');
      }
    }
    return false;
  }

  void appendInputAudio(String base64Data) {
    // MyLogger.info('Native WebSocket Realtime API append input audio: $base64Data');
    final appendInputAudioObject = {
      'type': 'input_audio_buffer.append',
      'audio': base64Data,
    };
    ws?.add(jsonEncode(appendInputAudioObject));
  }

  /// Handle chat interruption and audio playback
  /// Leave other events to eventHandler
  void _onData(dynamic data) {
    final json = jsonDecode(data);
    String type = json['type']!;
    if(type != 'response.audio.delta') { // Don't print the audio data
      MyLogger.info('Native WebSocket Realtime API: receive data: $data');
    }
    if(type == 'input_audio_buffer.speech_started') { // This means interrupt by user
      _onInterrupt();
    } else if(type == 'response.audio.delta') {
      MyLogger.info('Native WebSocket Realtime API: response.audio.delta');
      String? itemId = json['item_id'];
      final audioBase64 = json['delta'];
      final contentIndex = json['content_index'] as int;
      audioPlayerProxy.play(audioBase64, itemId?? '', contentIndex);
    }
    eventHandler.onData(json);
  }

  void _onError(Object error, StackTrace stackTrace) {
    MyLogger.err('Native WebSocket Realtime API: $error, stackTrace: $stackTrace');
    onWsError?.call(error, stackTrace);
  }

  void _onClose() {
    MyLogger.info('Native WebSocket Realtime API: close');
    onWsClose?.call();
  }

  void _onInterrupt() {
    MyLogger.info('Native WebSocket Realtime API: Interrupted');
    final truncateInfo = audioPlayerProxy.stop();
    if(truncateInfo != null) {
      MyLogger.info('Native WebSocket Realtime API: Interrupt, truncate info: ${truncateInfo.itemId} ${truncateInfo.contentIndex} ${truncateInfo.audioEndMs}');
      _truncate(truncateInfo);
    }
  }
  void _truncate(TruncateInfo truncateInfo) {
    final truncateObject = {
      'type': 'conversation.item.truncate',
      'item_id': truncateInfo.itemId,
      'content_index': truncateInfo.contentIndex,
      'audio_end_ms': truncateInfo.audioEndMs,
    };
    sendEvent(truncateObject);
  }
}