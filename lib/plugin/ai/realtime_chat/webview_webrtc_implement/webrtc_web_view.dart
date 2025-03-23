import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:my_log/my_log.dart';

class WebRtcRealtimeWebView extends StatefulWidget {
  final int sampleRate;
  final int numChannels;
  final int sampleSize;
  final String baseUrl;
  final String model;
  final String apiKey;
  final void Function(String data) onData;
  final void Function(InAppWebViewController controller) registerController;

  const WebRtcRealtimeWebView({
    super.key,
    required this.onData,
    required this.registerController,
    required this.sampleRate,
    required this.numChannels,
    required this.sampleSize,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  @override
  State<WebRtcRealtimeWebView> createState() => _WebRtcRealtimeWebViewState();
}

class _WebRtcRealtimeWebViewState extends State<WebRtcRealtimeWebView> {
  @override
  Widget build(BuildContext context) {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    return InAppWebView(
      initialFile: 'assets/webview/webrtc_realtime_page.html',
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
      ),
      onPermissionRequest: (controller, request) async {
        MyLogger.info('_WebRtcRealtimeWebViewState: onPermissionRequest: ${request.resources}');
        return PermissionResponse(resources: request.resources, action: PermissionResponseAction.GRANT);
      },
      onLoadStop: (controller, url) {
        MyLogger.info('_WebRtcRealtimeWebViewState: onLoadStop');
        _setupController(controller);
        _startRunning(controller);
        widget.registerController(controller);
      },
      onReceivedError: (controller, request, error) {
        MyLogger.warn('_WebRtcRealtimeWebViewState: onReceivedError: ${error.description}');
      },
      onConsoleMessage: (controller, message) {
        MyLogger.info('_WebRtcRealtimeWebViewState: onConsoleMessage: ${message.message}');
      },
      onMicrophoneCaptureStateChanged: (controller, oldState, newState) async {
        MyLogger.info('_WebRtcRealtimeWebViewState: onMicrophoneCaptureStateChanged: $oldState -> $newState');
      },
    );
  }

  void _setupController(InAppWebViewController controller) {
    controller.addJavaScriptHandler(handlerName: 'onData', callback: (args) {
      widget.onData(args[0]);
    });
  }

  void _startRunning(InAppWebViewController controller) {
    controller.evaluateJavascript(source: """
      start('${widget.baseUrl}', '${widget.model}', '${widget.apiKey}', ${widget.sampleRate}, ${widget.numChannels}, ${widget.sampleSize});
    """);
  }

}
