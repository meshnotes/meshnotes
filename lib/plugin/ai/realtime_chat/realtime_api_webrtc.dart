import 'dart:io';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:my_log/my_log.dart';
import 'package:http/http.dart' as http;

class RealtimeApiWebRtc {
  bool needSayHelloToUser = false;
  SimpleAudioRTC? _rtc;
  final String url = 'wss://api.openai.com/v1/realtime';
  final String _sessionUrl = 'https://api.openai.com/v1/realtime/sessions';
  final String _realtimeUrl = "https://api.openai.com/v1/realtime";
  final String model = 'gpt-4o-realtime-preview-2024-12-17';
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
  final void Function(String)? onAiTranscriptDelta;
  final void Function(String)? onAiTranscriptDone;
  final void Function(String)? onUserTranscriptDone;
  final void Function()? onFailed;
  final void Function()? onClose;
  final void Function(String, String, String)? onFunctionCall;

  // ignore: constant_identifier_names
  static const int MAX_RECONNECT_TIMES = 3;

  RealtimeApiWebRtc({
    required this.apiKey,
    this.toolsDescription,
    this.onAiTranscriptDelta,
    this.onAiTranscriptDone,
    this.onUserTranscriptDone,
    this.onFailed,
    this.onClose,
    this.onFunctionCall,
  });

  Future<bool> connectWebRtc({String? userContents, String? history}) async {
    if(_rtc != null) return true;

    _rtc = SimpleAudioRTC(onData: _onData, onClose: _onClose, onFailed: _onFailed);
    final token = await getEphmeralToken();
    await _rtc!.connect('$_realtimeUrl?model=$model', token);
    return true;
    // return await _connect(userContents, history);
  }

  Future<String> getEphmeralToken() async {
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final body = {
      'model': model,
      'voice': 'alloy',
    };
    try {
      final response = await http.post(
        Uri.parse(_sessionUrl),
        headers: headers,
        body: jsonEncode(body),
      );
      MyLogger.info('Realtime API: get ephmeral token response: ${response.body}');
      final json = jsonDecode(response.body);
      final clientSecret = json['client_secret'];
      MyLogger.info('Realtime API: get ephmeral token clientSecret: $clientSecret');
      if(clientSecret == null) {
        MyLogger.err('Realtime API: get ephmeral token failed from json: $json');
        return '';
      }
      final value = clientSecret['value'];
      MyLogger.info('Realtime API: get ephmeral token value: $value');
      if(value == null) {
        MyLogger.err('Realtime API: get ephmeral token failed from client_secret: $clientSecret');
        return '';
      }
      return value;
    } catch(e) {
      MyLogger.err('Realtime API: get ephmeral token failed: exception=$e');
      return '';
    }
  }

  void toggleMute(bool mute) {
    _rtc?.setMute(mute);
  }
  void endCall() {
    _rtc?.close();
    _rtc = null;
  }

  void shutdown() {
    _rtc?.close();
    _rtc = null;
  }

  // Future<bool> _connect(String? userContents, String? history) async {
  //   for(int i = 0; i < MAX_RECONNECT_TIMES; i++) {
  //     if(i > 0) {
  //       MyLogger.info('Realtime API: reconnecting for the $i-th time...');
  //     }
  //     var instructions = defaultInstructions;
  //     // Append user contents and history if any
  //     if(userContents != null) { // If there is user content, use the special instructions
  //       instructions = instructionsWithUserContent + '\n' + userContents;
  //     }
  //     if(history != null) {
  //       instructions = instructions + '\n' + history;
  //     }
  //     MyLogger.debug('Realtime API: instructions: $instructions');
  //     try {
  //       ws = await WebSocket.connect(
  //       '$url?model=$model',
  //       headers: {
  //         'Authorization': 'Bearer $apiKey',
  //         'OpenAI-Beta': 'realtime=v1',
  //         },
  //       );
  //       if(history != null || userContents != null) {
  //         updateSession(modifications: {
  //           'instructions': instructions,
  //         });
  //       } else {
  //         updateSession();
  //       }
  //       ws!.listen(_onData, onError: _onError, onDone: _onClose);
  //       if(needSayHelloToUser) {
  //         _sayHelloToUser();
  //       }
  //       return true;
  //     } catch(e) {
  //       MyLogger.err('Realtime API connect failed: $e');
  //     }
  //   }
  //   return false;
  // }

  String _generateEventId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  void updateSession({Map<String, dynamic>? modifications}) {
    Map<String, dynamic> sessionObject = {
      'modalities': ['text', 'audio'],
      'instructions': defaultInstructions,
      'voice': 'alloy',
      'input_audio_transcription': {
        'model': 'whisper-1',
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
    MyLogger.info('Realtime API update session: $updateSessionObject');
    _rtc?.sendData(jsonEncode(updateSessionObject));
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
    _rtc?.sendData(jsonEncode(sendFunctionResultObject));
  }
  // Called when the function call result need to be informed to user
  void informUserToolResult(String callId) {
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
    _rtc?.sendData(jsonEncode(responseCreateObject));
  }

  void _onData(String data) {
    final json = jsonDecode(data);
    String type = json['type']!;
    String? eventId = json['event_id'];
    String? itemId = json['item_id'];
    if(type.startsWith('session.')) {
      _onSession(type, eventId, itemId, json);
    } else if(type.startsWith('response.')) {
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

  void _onClose() {
    MyLogger.info('Realtime API: close');
    onClose?.call();
  }
  void _onFailed() {
    MyLogger.info('Realtime API: failed');
    onFailed?.call();
  }

  /// session.created
  /// session.updated
  void _onSession(String type, String? eventId, String? itemId, Map<String, dynamic> json) {
    if(type == 'session.created') {
      updateSession(); // Update session after created, or update will be failed
    }
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
    if(type == 'response.audio_transcript.delta') {
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
      // onInterrupt?.call();
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

class SimpleAudioRTC {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  RTCDataChannel? _dataChannel;
  final void Function(String)? onData;
  final void Function()? onClose;
  final void Function()? onFailed;

  SimpleAudioRTC({
    this.onData,
    this.onClose,
    this.onFailed,
  });

  // Connect and finish OA negotiate
  connect(String url, String token) async {
    try {
      // 1. Create peer connection
      final configuration = <String, dynamic>{
        // 'iceServers': [
        //   {'urls': 'stun:stun.l.google.com:19302'},
        // ],
      };
      
      _peerConnection = await createPeerConnection(configuration, {});
      
      // 2. Add audio track
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
          'googHighpassFilter': true,
          'googAudioMirroring': false,
          'googDucking': false,
        },
        'video': false
      });
      
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      final dataChannelInit = RTCDataChannelInit()
        ..ordered = true
        ..maxRetransmits = 30
        ..protocol = 'json'
        ..negotiated = false;
      final dc = await _peerConnection!.createDataChannel('oai-events', dataChannelInit);
      // dc.onDataChannelState = (RTCDataChannelState state) {
      //   if(state == RTCDataChannelState.RTCDataChannelOpen) {
      //   } else if(state == RTCDataChannelState.RTCDataChannelClosed) {
      //     onClose?.call();
      //   }
      // };
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) { // OpenAI will timeout after 30 minutes, let application handle and reconnect
        if(state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          MyLogger.info('Realtime API state: peer connection disconnected');
        } else if(state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          onFailed?.call();
          MyLogger.info('Realtime API state: peer connection failed');
        } else if(state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          onClose?.call();
          MyLogger.info('Realtime API state: peer connection closed');
        }
      };
      dc.onMessage = (RTCDataChannelMessage message) {
        // Will receive type='text' message from OpenAI
        MyLogger.info('Realtime API: data channel message: type=${message.type}, text=${message.text}');
        onData?.call(message.text);
      };
      _dataChannel = dc;
      
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/sdp',
      };
      try {
        final client = http.Client();
        final request = http.Request('POST', Uri.parse(url));
        request.headers.addAll(headers);
        request.body = offer.sdp!;
        request.headers['Content-Type'] = 'application/sdp'; // Override the default content type, which will add charset=utf-8
        final response = await client.send(request);
        if(response.statusCode != HttpStatus.ok && response.statusCode != HttpStatus.created) {
          MyLogger.err('Realtime API: create offer failed: ${response.statusCode}');
          return null;
        }
        final responseBody = await response.stream.bytesToString();
        final answerSdp = responseBody;
        MyLogger.info('Realtime API: create offer response: ${response.statusCode}');
        await _peerConnection!.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
      } catch(e) {
        MyLogger.err('Realtime API: create offer failed: exception=$e');
        return '';
      }
    } catch (e) {
      MyLogger.err('Realtime API: connect failed: exception=$e');
      return null;
    }
  }

  void sendData(String data) {
    _dataChannel!.send(RTCDataChannelMessage(data));
  }
  
  void setMute(bool mute) {
    if (_localStream != null) {
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = !mute;
      });
    }
  }
  
  Future<void> close() async {
    MyLogger.info('Realtime API: close');
    try {
      // Stop local stream
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) => track.stop());
        _localStream?.getAudioTracks().forEach((track) => track.stop());
        await _localStream!.dispose();
        _localStream = null;
      }
      
      // Close peer connection
      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }
    } catch (e) {
      MyLogger.err('Error closing WebRTC connection: $e');
    }
  }
}