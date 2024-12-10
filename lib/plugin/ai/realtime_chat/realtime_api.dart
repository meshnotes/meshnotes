import 'dart:io';
import 'dart:convert';
import 'package:my_log/my_log.dart';
import 'playing_buffer_info_manager.dart';

class RealtimeApi {
  bool needSayHelloToUser = false;
  final String url = 'wss://api.openai.com/v1/realtime';
  final String model = 'gpt-4o-realtime-preview-2024-10-01';
  final String apiKey;
  final List<Map<String, dynamic>>? toolsDescription;
  final String defaultInstructions = 'You are a helpful assistant, try to chat with user or answer the user\'s question politely.';
  final String instructionsWithUserContent = '''
You are an intelligent assistant for MeshNotes(an notebook app), 
equipped with extensive knowledge. Users will share their notes with you. 
Please engage in conversation with users based on these notes. 
During the chat, user may want to talk about the notes, or just chatting
with you, or talk anything they want. Please be friendly and helpful.
Use your vast knowledge to offer suggestions, encouragement, and inspiration to users.

Chatting Instructions:
1. Keep the reply concise and clear, reducing formalities and red tape.
2. Use the setting language by default. In cases where it is not set, default to use English.
3. If you are not sure about the user's question, you can take the initiative to ask the user to repeat it.
''';
  WebSocket? ws;
  final void Function(String, String, int)? onAiAudioDelta;
  final void Function(String)? onAiTranscriptDelta;
  final void Function(String)? onAiTranscriptDone;
  final void Function(String)? onUserTranscriptDone;
  final void Function()? onInterrupt;
  final void Function(Object, StackTrace)? onWsError;
  final void Function()? onWsClose;
  final void Function(String, String, String)? onFunctionCall;

  // ignore: constant_identifier_names
  static const int MAX_RECONNECT_TIMES = 3;

  RealtimeApi({
    required this.apiKey,
    this.toolsDescription,
    this.onAiAudioDelta,
    this.onInterrupt,
    this.onAiTranscriptDelta,
    this.onAiTranscriptDone,
    this.onUserTranscriptDone,
    this.onWsError,
    this.onWsClose,
    this.onFunctionCall,
  });

  Future<bool> connect({String? userContents, String? history}) async {
    return await _connect(userContents, history);
  }

  void shutdown() {
    ws?.close();
  }

  Future<bool> _connect(String? userContents, String? history) async {
    for(int i = 0; i < MAX_RECONNECT_TIMES; i++) {
      if(i > 0) {
        MyLogger.info('Realtime API: reconnecting for the $i-th time...');
      }
      var instructions = defaultInstructions;
      // Append user contents and history if any
      if(userContents != null) { // If there is user content, use the special instructions
        instructions = instructionsWithUserContent + '\n' + userContents;
      }
      if(history != null) {
        instructions = instructions + '\n' + history;
      }
      MyLogger.debug('Realtime API: instructions: $instructions');
      try {
        ws = await WebSocket.connect(
        '$url?model=$model',
        headers: {
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'realtime=v1',
          },
        );
        if(history != null || userContents != null) {
          updateSession(modifications: {
            'instructions': instructions,
          });
        } else {
          updateSession();
        }
        ws!.listen(_onData, onError: _onError, onDone: _onClose);
        if(needSayHelloToUser) {
          _sayHelloToUser();
        }
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
      'tools': toolsDescription?? [],
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
    MyLogger.debug('Realtime API update session: $updateSessionObject');
    ws!.add(jsonEncode(updateSessionObject));
  }

  void appendInputAudio(String base64Data) {
    // MyLogger.info('Realtime API append input audio: $base64Data');
    final appendInputAudioObject = {
      'type': 'input_audio_buffer.append',
      'audio': base64Data,
    };
    ws?.add(jsonEncode(appendInputAudioObject));
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

  // Called when function call is done
  void sendFunctionResult(String callId, String result) {
    final sendFunctionResultObject = {
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': callId,
        'output': result,
      },
    };
    ws!.add(jsonEncode(sendFunctionResultObject));
  }
  // Called when the function call result need to be informed to user
  void informUserToolResult(String callId) {
    _sendResponseCreate('please tell user about the tool result of call_id=$callId.');
  }

  void _sayHelloToUser() {
    _sendResponseCreate('Now play a "dong" sound to inform user that you are ready to chat with him.');
  }

  void _sendResponseCreate(String text) {
    final responseCreateObject = {
      'type': 'response.create',
      'response': {
        'modalities': ['text', 'audio'],
        'instructions': text,
      },
    };
    ws!.add(jsonEncode(responseCreateObject));
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
      MyLogger.info('Realtime API: response.audio.delta');
      final audioBase64 = json['delta'];
      final contentIndex = json['content_index'] as int;
      onAiAudioDelta?.call(audioBase64, itemId?? '', contentIndex);
    } else if(type == 'response.audio_transcript.delta') {
      final text = json['delta'] as String;
      onAiTranscriptDelta?.call(text);
    } else if(type == 'response.audio_transcript.done') {
      final text = json['transcript'] as String;
      onAiTranscriptDone?.call(text);
    } else if(type == 'response.function_call_arguments.done') {
      final callId = json['call_id'] as String;
      final name = json['name'] as String;
      final arguments = json['arguments'] as String;
      onFunctionCall?.call(callId, name, arguments);
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