import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:my_log/my_log.dart';

class AecAudioWebView extends StatefulWidget {
  final int sampleRate;
  final int numChannels;
  final int sampleSize;
  final String baseUrl;
  final String model;
  final String apiKey;
  final void Function(String base64Data) onData;
  final void Function(InAppWebViewController controller) registerController;

  const AecAudioWebView({
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
  State<AecAudioWebView> createState() => _AecAudioWebViewState();
}

class _AecAudioWebViewState extends State<AecAudioWebView> {
  @override
  Widget build(BuildContext context) {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    return InAppWebView(
      initialFile: 'assets/webview/websocket_realtime_page.html',
      onPermissionRequest: (controller, request) async {
        MyLogger.info('_AecAudioWebViewState: onPermissionRequest: ${request.resources}');
        return PermissionResponse(resources: request.resources, action: PermissionResponseAction.GRANT);
      },
      onLoadStop: (controller, url) {
        MyLogger.info('_AecAudioWebViewState: onLoadStop');
        _setupController(controller);
        _startRunning(controller);
        widget.registerController(controller);
      },
      onReceivedError: (controller, request, error) {
        MyLogger.warn('_AecAudioWebViewState: onReceivedError: ${error.description}');
      },
      onConsoleMessage: (controller, message) {
        MyLogger.info('_AecAudioWebViewState: onConsoleMessage: ${message.message}');
      },
      onMicrophoneCaptureStateChanged: (controller, oldState, newState) async {
        MyLogger.info('_AecAudioWebViewState: onMicrophoneCaptureStateChanged: $oldState -> $newState');
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
