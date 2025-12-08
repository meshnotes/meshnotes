/// WebView + WebSocket implementation
/// Support AEC(Acoustic Echo Cancellation)
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../realtime_api.dart';
import 'webrtc_web_view.dart';
import 'dart:convert';
import 'package:my_log/my_log.dart';

class RealtimeWebViewWebRtcApi extends RealtimeApi {
  final aecAudioWebViewKey = GlobalKey();
  final String url = 'https://api.openai.com/v1/realtime';
  final String model = 'gpt-realtime';
  final String apiKey;
  final List<Map<String, dynamic>>? toolsDescription;
  final void Function(Object, StackTrace)? onWsError;
  final void Function()? onWsClose;
  InAppWebViewController? webviewController;

  // ignore: constant_identifier_names
  static const int MAX_RECONNECT_TIMES = 3;

  RealtimeWebViewWebRtcApi({
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
    return true;
  }

  @override
  void shutdown() {
    // webviewController?.evaluateJavascript(source: 'shutdownAll()');
  }

  @override
  void sendEvent(Map<String, dynamic> event) {
    final json = jsonEncode(event);
    final base64 = base64Encode(utf8.encode(json));
    webviewController?.evaluateJavascript(source: 'sendBase64Event("$base64")');
  }
 
  @override
  void toggleMute(bool mute) {
    if(mute) {
      webviewController?.evaluateJavascript(source: 'mute()');
    } else {
      webviewController?.evaluateJavascript(source: 'unmute()');
    }
  }

  @override
  Widget? buildWebview() {
    final aecAudioWebView = WebRtcRealtimeWebView(
      key: aecAudioWebViewKey,
      baseUrl: url,
      model: model,
      apiKey: apiKey,
      sampleRate: sampleRate,
      numChannels: numChannels,
      sampleSize: sampleSize,
      onData: _onData,
      registerController: (controller) {
        webviewController = controller;
      },
    );
    return aecAudioWebView;
  }

  @override
  void playAudio(String audioBase64) {
    webviewController?.evaluateJavascript(source: 'playAudio("$audioBase64")');
  }

  void _onData(String data) {
    final json = jsonDecode(data);
    String type = json['type']!;
    if(type != 'response.audio.delta') { // Don't print the audio data
      MyLogger.info('RealtimeWebViewWebRtcApi: receive data: $data');
    }
    eventHandler.onData(json);
  }
}
