const overlayMessageTypeHello = 'hello';

class HelloMessage {
  String deviceId;

  HelloMessage(this.deviceId);

  HelloMessage.fromJson(Map<String, dynamic> json): deviceId = json['device_id'];

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
  };
}
