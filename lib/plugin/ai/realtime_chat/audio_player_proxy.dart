import 'dart:async';
import 'dart:typed_data';
import 'dart:collection';
import 'package:mp_audio_stream/mp_audio_stream.dart';
import 'package:my_log/my_log.dart';


class AudioItem {
  Float32List data;
  String itemId;
  int contentIndex;
  AudioItem(this.data, this.itemId, this.contentIndex);
}

class TruncateInfo {
  String itemId;
  int contentIndex;
  int audioEndMs;
  TruncateInfo(this.itemId, this.contentIndex, this.audioEndMs);
}

class AudioPlayerProxy {
  final AudioStream audioStream = getAudioStream();
  final Queue<AudioItem> audioQueue = Queue<AudioItem>();
  bool isPlaying = false;
  bool needStop = false;
  static const int sampleRate = 24000;
  StreamController<AudioItem>? audioStreamController;
  StreamSubscription<AudioItem>? audioStreamSubscription;
  AudioItem? currentAudioItem;
  String currentItemId = '';
  int currentContentIndex = 0;
  int startPointInCurrentItemId = 0;
  int currentPlayedMs = 0;
  Function? onPlaying;

  AudioPlayerProxy({
    this.onPlaying,
  }) {
    audioStream.init(channels: 1, sampleRate: sampleRate);
  }

  void resume() {
    audioStream.resume();
  }

  void shutdown() {
    isPlaying = false;
    needStop = true;
    audioStream.uninit();
  }

  // int _getCurrentPointInMillis() {
  //   return audioStream.stat().exhaust * 1000;
  // }

  // Future<void> _onAudioItem(AudioItem item) async {
  //   currentAudioItem = item;
  //   final audioData = item.data;
  //   final itemId = item.itemId;
  //   if(currentItemId != itemId) {
  //     currentItemId = itemId;
  //     startPointInCurrentItemId = _getCurrentPointInMillis();
  //   }

  //   audioStream.push(audioData);
  //   int delayMilliseconds = (audioData.length / sampleRate * 1000).toInt();
  //   MyLogger.debug('Audio player delay $delayMilliseconds ms');
  //   await Future.delayed(Duration(milliseconds: delayMilliseconds));
  //   MyLogger.info('Audio player delay $delayMilliseconds ms. already played ${_getCurrentPointInMillis() - startPointInCurrentItemId} ms');
  // }

  // TruncateInfo? stop() {
  //   audioStreamController?.close();
  //   audioStreamSubscription?.cancel();
  //   audioStreamController = null;
  //   audioStreamSubscription = null;
  //   int currentPoint = _getCurrentPointInMillis();
  //   if(currentAudioItem != null) {
  //     return TruncateInfo(currentAudioItem!.itemId, currentAudioItem!.contentIndex, currentPoint);
  //   }
  //   return null;
  // }

  // void play(Uint8List data, String itemId, int contentIndex) {
  //   if(audioStreamController == null) {
  //     audioStreamController = StreamController<AudioItem>();
  //     audioStreamSubscription = audioStreamController!.stream.asBroadcastStream().listen((item) async {
  //       await _onAudioItem(item);
  //     });
  //     currentItemId = '';
  //     startPointInCurrentItemId = 0;
  //   }
  //   // Convert Uint8List to PCM16
  //   final len = data.length ~/ 2;
  //   ByteData byteData = ByteData.sublistView(data);
  //   Float32List floatData = Float32List(len);
  //   for(int i = 0; i < len; i++) {
  //     final pcm16 = byteData.getInt16(i * 2, Endian.little);
  //     floatData[i] = pcm16 / 32768.0; // Normalize to [-1.0, 1.0]
  //   }

  //   audioStreamController!.add(AudioItem(floatData, itemId, contentIndex));
  // }


  TruncateInfo? stop() {
    audioQueue.clear();
    audioStream.resetStat();
    // audioStreamController?.close();
    // audioStreamSubscription?.cancel();
    // audioStreamController = null;
    // audioStreamSubscription = null;
    // int currentPoint = _getCurrentPointInMillis();
    if(currentItemId != '') {
      return TruncateInfo(currentItemId, currentContentIndex, currentPlayedMs);
    }
    return null;
  }

  void play(Uint8List data, String itemId, int contentIndex) {
    if (!isPlaying) {
      currentItemId = '';
      currentContentIndex = 0;
      startPointInCurrentItemId = 0;
      currentPlayedMs = 0;
      start();
    }
    // Convert Uint8List to PCM16
    final len = data.length ~/ 2;
    ByteData byteData = ByteData.sublistView(data);
    Float32List floatData = Float32List(len);
    for (int i = 0; i < len; i++) {
      final pcm16 = byteData.getInt16(i * 2, Endian.little);
      floatData[i] = pcm16 / 32768.0; // Normalize to [-1.0, 1.0]
    }

    // Add floatData to queue instead of pushing directly
    audioQueue.add(AudioItem(floatData, itemId, contentIndex));
    //audioStream.push(floatData);
  }

  void start() {
    loop();
  }

  void loop() async {
    isPlaying = true;
    MyLogger.info('AudioPlayerProxy loop start');
    while(!needStop) {
      if (audioQueue.isNotEmpty) {
        final item = audioQueue.removeFirst();
        final audioData = item.data;
        final itemId = item.itemId;
        final contentIndex = item.contentIndex;
        if(currentItemId != itemId) {
          currentItemId = itemId;
          currentContentIndex = contentIndex;
          currentPlayedMs = 0;
        }
        final len = audioData.length;
        int delayMilliseconds = (len / sampleRate * 1000).toInt();
        MyLogger.debug('AudioPlayerProxy loop delay $delayMilliseconds ms');
        audioStream.push(audioData);
        onPlaying?.call();
        await Future.delayed(Duration(milliseconds: delayMilliseconds));
        currentPlayedMs += delayMilliseconds;
      } else {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
    MyLogger.info('AudioPlayerProxy loop end');
  }
}