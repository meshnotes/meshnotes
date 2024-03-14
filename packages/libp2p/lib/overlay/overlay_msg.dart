const overlayMessageTypeHello = 'hello';

class HelloMessage {
  String deviceId;
  String name;
  String publicKey;

  HelloMessage(this.deviceId, this.name, this.publicKey);

  HelloMessage.fromJson(Map<String, dynamic> map): deviceId = map['device_id'], name = map['name'], publicKey = map['public'];

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'name': name,
    'public': publicKey,
  };
}
