class RealtimeEventHandler {
  void Function(Map<String, dynamic> data) onData; // callback if receive message need to be handled by application
  void Function(String error) onError; // callback if error occurs
  void Function() onClose; // callback if connection is closed
  void Function(int duration)? onPlaying; // callback if playing audio(usually used for playing animation effect)

  RealtimeEventHandler({
    required this.onData,
    required this.onError,
    required this.onClose,
    this.onPlaying,
  });
}
abstract class RealtimeApi {
  final RealtimeEventHandler eventHandler;
  RealtimeApi({required this.eventHandler});

  Future<bool> connect();
  void shutdown();
  void sendEvent(Map<String, dynamic> event);
  void toggleMute(bool mute);
}
