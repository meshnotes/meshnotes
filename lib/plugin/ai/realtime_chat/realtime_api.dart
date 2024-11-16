import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:my_log/my_log.dart';

import 'audio_player_proxy.dart';

class RealtimeApi {
  final String url = 'wss://api.openai.com/v1/realtime';
  final String model = 'gpt-4o-realtime-preview-2024-10-01';
  final String apiKey;
  final String defaultInstructions = 'You are a helpful assistant, try to chat with user or answer the user\'s question politely.';
  WebSocket? ws;
  final void Function(Uint8List, String, int)? onAiAudioDelta;
  final void Function(String)? onAiTranscriptDelta;
  final void Function(String)? onAiTranscriptDone;
  final void Function(String)? onUserTranscriptDone;
  final void Function()? onInterrupt;
  final void Function(Object, StackTrace)? onWsError;
  final void Function()? onWsClose;

  // ignore: constant_identifier_names
  static const int MAX_RECONNECT_TIMES = 3;

  RealtimeApi({
    required this.apiKey,
    this.onAiAudioDelta,
    this.onInterrupt,
    this.onAiTranscriptDelta,
    this.onAiTranscriptDone,
    this.onUserTranscriptDone,
    this.onWsError,
    this.onWsClose,
  });

  Future<bool> connect() async {
    return await _connect(null);
  }

  Future<bool> reconnect({String? history}) async {
    return await _connect(history);
  }

  void shutdown() {
    ws?.close();
  }

  Future<bool> _connect(String? history) async {
    for(int i = 0; i < MAX_RECONNECT_TIMES; i++) {
      if(i > 0) {
        MyLogger.info('Realtime API: reconnecting for the $i-th time...');
      }
      try {
        ws = await WebSocket.connect(
        '$url?model=$model',
        headers: {
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'realtime=v1',
          },
        );
        if(history != null) {
          final instructions = defaultInstructions + '\nPlease follow the previous conversation history, AI means you, and user means the user.\n' + history;
          updateSession(modifications: {
            'instructions': instructions,
          });
        } else {
          updateSession();
        }
        ws!.listen(_onData, onError: _onError, onDone: _onClose);
        return true;
      } catch(e) {
        MyLogger.err('Realtime API connect failed: $e');
      }
    }
    return false;
  }

  String _generateEventId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  void updateSession({Map<String, dynamic>? modifications}) {
    Map<String, dynamic> sessionObject = {
      'modalities': ['text', 'audio'],
      'instructions': defaultInstructions,
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
      'tools': [],
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
    MyLogger.info('Realtime API: $updateSessionObject');
    ws!.add(jsonEncode(updateSessionObject));
  }

  void appendInputAudio(Uint8List data) {
    final appendInputAudioObject = {
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(data),
    };
    ws!.add(jsonEncode(appendInputAudioObject));
  }

  void truncate(TruncateInfo truncateInfo) {
    final truncateObject = {
      'type': 'conversation.item.truncate',
      'item_id': truncateInfo.itemId,
      'content_index': truncateInfo.contentIndex,
      'audio_end_ms': truncateInfo.audioEndMs,
    };
    ws!.add(jsonEncode(truncateObject));
  }

  void _onData(dynamic data) {
    final json = jsonDecode(data);
    String type = json['type']!;
    String? eventId = json['event_id'];
    String? itemId = json['item_id'];
    if(type.startsWith('response.')) {
      _onResponse(type, eventId, itemId, json);
    } else if(type.startsWith('input')) {
      _onInput(type, eventId, itemId, json);
    } else if(type.startsWith('conversation.')) {
      _onConversation(type, eventId, itemId, json);
    } else if(type == 'error') {
      final errorBody = json['error'];
      final errorType = errorBody['type'];
      final errorCode = errorBody['code'];
      final errorMessage = errorBody['message'];
      _onApplicationError(errorType, errorCode, errorMessage);
    } else {
      MyLogger.info('Realtime API: $json');
    }

    // Other events
    // rate_limits.updated
  }

  void _onError(Object error, StackTrace stackTrace) {
    MyLogger.err('Realtime API: $error, stackTrace: $stackTrace');
    onWsError?.call(error, stackTrace);
  }

  void _onClose() {
    MyLogger.info('Realtime API: close');
    onWsClose?.call();
  }

  /// response.created: with response id in json['response']['id']
  /// response.output_item.added: with item id in json['item']['id']
  /// response.audio.delta: json['delta'], audio base64 string, PCM16, mono channel, 24000 Hz
  /// response.audio.done: no any useful information
  /// response.audio_transcript.delta: json['delta'], delta transcript text
  /// response.audio_transcript.done: full audio transcript text
  /// response.output_item.done: audio transcript
  /// response.content_part.done: full audio transcript text
  /// response.done: audio transcript, with usage information
  void _onResponse(String type, String? eventId, String? itemId, Map<String, dynamic> json) {
    // String? responseId = json['response_id'];
    if(type == 'response.audio.delta') {
      final audioBase64 = json['delta'];
      final audio = base64Decode(audioBase64!);
      final contentIndex = json['content_index'] as int;
      onAiAudioDelta?.call(audio, itemId?? '', contentIndex);
    } else if(type == 'response.audio_transcript.delta') {
      final text = json['delta'] as String;
      onAiTranscriptDelta?.call(text);
    } else if(type == 'response.audio_transcript.done') {
      final text = json['transcript'] as String;
      onAiTranscriptDone?.call(text);
    } else {
      MyLogger.debug('Realtime API: $json');
    }
  }

  /// input_audio_buffer.speech_started
  /// input_audio_buffer.speech_stopped
  /// input_audio_buffer.committed
  void _onInput(String type, String? eventId, String? itemId, Map<String, dynamic> json) {
    if(type == 'input_audio_buffer.speech_started') { // This means interrupt by user
      onInterrupt?.call();
    } else if(type == 'input_audio_buffer.speech_stopped') {
      // onSpeechStopped();
    } else if(type == 'input_audio_buffer.committed') {
      // onAudioCommitted();
    }
  }

  /// conversation.item.created
  /// conversation.item.input_audio_transcription.completed: user audio transcript
  void _onConversation(String type, String? eventId, String? itemId, Map<String, dynamic> json) {
    MyLogger.debug('Realtime API: $json');
    if(type == 'conversation.item.input_audio_transcription.completed') {
      final text = json['transcript'];
      onUserTranscriptDone?.call(text);
    }
  }

  void _onApplicationError(String? errorType, String? errorCode, String? errorMessage) {
    MyLogger.err('Realtime error: type=$errorType, code=$errorCode, message=$errorMessage');
  }
}