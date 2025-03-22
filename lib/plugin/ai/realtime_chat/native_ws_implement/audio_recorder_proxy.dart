import 'dart:convert';

import 'package:record/record.dart';

import '../realtime_ws_helper.dart';

class NativeAudioRecorderProxy extends AudioRecorderProxy {
  void Function(String base64Data)? _onAudioData;
  late AudioRecorder record;
  bool shouldStop = false;
  final int sampleRate;
  final int numChannels;

  NativeAudioRecorderProxy({
    required this.sampleRate,
    required this.numChannels,
  });

  @override
  void start() async {
    record = AudioRecorder();
    if(await record.hasPermission()) {
      final stream = await record.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: numChannels,
        sampleRate: sampleRate,
      ));
      stream.listen((data) {
        if(shouldStop) {
          return;
        }
        _onAudioData?.call(base64Encode(data));
      });
    }
  }

  @override
  void stop() {
    shouldStop = true;
    record.stop();
  }

  @override
  void mute() {
    record.pause();
  }
  @override
  void unmute() {
    record.resume();
  }
  
  @override
  void setOnAudioData(void Function(String base64Data) onAudioData) {
    _onAudioData = onAudioData;
  }
}
