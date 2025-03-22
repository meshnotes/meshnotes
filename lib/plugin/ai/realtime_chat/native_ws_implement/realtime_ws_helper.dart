class TruncateInfo {
  String itemId;
  int contentIndex;
  int audioEndMs;
  TruncateInfo(this.itemId, this.contentIndex, this.audioEndMs);
}

abstract class AudioPlayerProxy {
  void play(String base64Data, String itemId, int contentIndex, {double volume=1.0});
  void start();
  void shutdown();
  void resume();
  TruncateInfo? stop();
}

abstract class AudioRecorderProxy {
  void start();
  void shutdown();
  void mute();
  void unmute();
  void setOnAudioData(void Function(String base64Data) onAudioData);
}


class PlayingBufferInfoManager {
  _PlayingBufferInfo? _currentPlayingBufferInfo;
  int? _startTimeMsAtTheBeginning;

  void updatePlayingBufferInfo(String itemId, int contentIndex, int startTimeMs) {
    final oldItemId = _currentPlayingBufferInfo?.itemId;
    if(oldItemId != itemId || _startTimeMsAtTheBeginning == null) {
      _startTimeMsAtTheBeginning = startTimeMs;
    }
    _currentPlayingBufferInfo = _PlayingBufferInfo(itemId: itemId, contentIndex: contentIndex, startTimeMs: startTimeMs);
  }
  
  void playEnded() {
    _currentPlayingBufferInfo = null;
    _startTimeMsAtTheBeginning = null;
  }

  TruncateInfo? getTruncateInfo() {
    if(_currentPlayingBufferInfo == null || _startTimeMsAtTheBeginning == null) {
      return null;
    }
    final result = TruncateInfo(
      _currentPlayingBufferInfo!.itemId,
      _currentPlayingBufferInfo!.contentIndex,
      _currentPlayingBufferInfo!.startTimeMs - _startTimeMsAtTheBeginning!,
    );
    playEnded();
    return result;
  }
}

class _PlayingBufferInfo {
  final String itemId;
  final int contentIndex;
  final int startTimeMs;

  _PlayingBufferInfo({
    required this.itemId,
    required this.contentIndex,
    required this.startTimeMs,
  });
}