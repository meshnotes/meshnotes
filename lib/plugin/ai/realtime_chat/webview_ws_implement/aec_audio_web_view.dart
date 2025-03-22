import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:my_log/my_log.dart';
import '../realtime_ws_helper.dart';

class AecAudioWebView extends StatefulWidget {
  final Function(AudioPlayerProxy, AudioRecorderProxy) onAudioProxyReady;
  final int sampleRate;
  final int numChannels;
  final int sampleSize;

  const AecAudioWebView({
    super.key,
    required this.onAudioProxyReady,
    required this.sampleRate,
    required this.numChannels,
    required this.sampleSize,
  });

  @override
  State<AecAudioWebView> createState() => _AecAudioWebViewState();
}

class _AecAudioWebViewState extends State<AecAudioWebView> {
  _InWebViewAudioPlayerProxy? _audioPlayerProxy;
  _InWebAudioRecorderProxy? _audioRecorderProxy;

  @override
  Widget build(BuildContext context) {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    return InAppWebView(
      initialFile: 'assets/webview/aec_audio_page.html',
      onPermissionRequest: (controller, request) async {
        MyLogger.info('onPermissionRequest: ${request.resources}');
        return PermissionResponse(resources: request.resources, action: PermissionResponseAction.GRANT);
      },
      onLoadStop: (controller, url) {
        MyLogger.info('onLoadStop');
        _setupController(controller);
        _startPlayerAndRecorder(controller);
      },
      onReceivedError: (controller, request, error) {
        MyLogger.warn('onReceivedError: ${error.description}');
      },
      onConsoleMessage: (controller, message) {
        MyLogger.info('onConsoleMessage: ${message.message}');
      },
      onMicrophoneCaptureStateChanged: (controller, oldState, newState) async {
        MyLogger.info('onMicrophoneCaptureStateChanged: $oldState -> $newState');
      },
    );
  }

  void _setupController(InAppWebViewController controller) {
    controller
      ..addJavaScriptHandler(handlerName: 'onAudioActive', callback: (args) {
        MyLogger.info('onAudioActive: $args');
      })
      ..addJavaScriptHandler(handlerName: 'onAudioData', callback: (args) {
        MyLogger.info('onAudioData: $args');
      })
      ..addJavaScriptHandler(handlerName: 'onMicAudioData', callback: (List<dynamic> args) {
        // MyLogger.info('onMicAudioData: $args');
        final data = args[0] as String;
        // MyLogger.info('onMicAudioData: $data');
        _audioRecorderProxy?.appendInputAudio(data);
      })
      ..addJavaScriptHandler(handlerName: 'onPlayingBufferEnd', callback: (args) {
        _audioPlayerProxy?.clearPlayingBuffers();
      })
      ..addJavaScriptHandler(handlerName: 'onPlayingNextBuffer', callback: (args) {
        final itemId = args[0] as String;
        final contentIndex = args[1] as int;
        final startTime = args[2] as double;
        final endTime = args[3] as double;
        MyLogger.info('onPlayingNextBuffer: $itemId $contentIndex $startTime $endTime');
        _audioPlayerProxy?.setPlayingBufferInfo(itemId, contentIndex, startTime * 1000);
      })
      ..addJavaScriptHandler(handlerName: 'onAudioReady', callback: (args) {
        MyLogger.info('onAudioReady, start realtime chat now');
        _audioPlayerProxy = _InWebViewAudioPlayerProxy(controller: controller);
        _audioRecorderProxy = _InWebAudioRecorderProxy(controller: controller);
        widget.onAudioProxyReady(_audioPlayerProxy!, _audioRecorderProxy!);
      })
    ;
  }

  void _startPlayerAndRecorder(InAppWebViewController controller) {
    controller.evaluateJavascript(source: """
      startRecording(${widget.sampleRate}, ${widget.numChannels}, ${widget.sampleSize});
      startPlayer();
    """);
  }

}

class _InWebViewAudioPlayerProxy extends AudioPlayerProxy {
  final InAppWebViewController controller;
  final PlayingBufferInfoManager playingBufferInfoManager = PlayingBufferInfoManager();

  _InWebViewAudioPlayerProxy({required this.controller});

  void clearPlayingBuffers() {
    playingBufferInfoManager.playEnded();
  }
  void setPlayingBufferInfo(String itemId, int contentIndex, double startTimeMs) {
    playingBufferInfoManager.updatePlayingBufferInfo(itemId, contentIndex, startTimeMs.toInt());
  }

  @override
  void play(String base64Data, String itemId, int contentIndex) {
    MyLogger.info('play data');
    controller.evaluateJavascript(
      source: 'playAudio("$base64Data", "$itemId", $contentIndex);'
    );
  }
  
  @override
  void resume() {
    // TODO: implement resume
  }
  
  @override
  void shutdown() {
    MyLogger.info('shutdown');
//     controller.evaluateJavascript(source: """
//       stop();
// """).then((result) {
//       MyLogger.info('stop: $result');
//     });
  }
  
  @override
  void start() {
    // TODO: implement start
  }
  
  @override
  TruncateInfo? stop() {
    // Float32List data = Float32List(100);
    // for(int i = 0; i < data.length; i++) {
    //   data[i] = 2.0 * i;
    // }
    // MyLogger.info('stop');
    // controller.evaluateJavascript(source: 'play($data);').then((result) {
    //   MyLogger.info('stop: $result');
    // });
    controller.evaluateJavascript(source: 'clearPlayingBuffers();');
    return playingBufferInfoManager.getTruncateInfo();
  }
}

class _InWebAudioRecorderProxy extends AudioRecorderProxy {
  final InAppWebViewController controller;
  void Function(String base64Data)? _onAudioData;

  _InWebAudioRecorderProxy({
    required this.controller,
  });

  void appendInputAudio(String base64Data) {
    _onAudioData?.call(base64Data);
  }
  
  @override
  void start() {
    // Won't be called, do nothing
  }
  
  @override
  void stop() {
    // TODO: implement stop
  }

  @override
  void mute() {
    // controller.evaluateJavascript(source: 'testMicAudioBuffer();');
    controller.evaluateJavascript(source: 'mute();');
  }
  @override
  void unmute() {
    controller.evaluateJavascript(source: 'unmute();');
  }

  @override
  void setOnAudioData(void Function(String base64Data) onAudioData) {
    _onAudioData = onAudioData;
  }
}
