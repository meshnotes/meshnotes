import 'dart:convert';

import 'frame.dart';
import 'util.dart';

enum PacketType {
  connect,    // initialize connect from client
  connectAck, // response connect_ack from server
  connected,  // response connected from client, connection established
  data,       // send data frames
  announce,   // broadcast
  invalid,
}

class PacketHeader {
  PacketType type;
  int destConnectionId;
  int packetNumber;

  PacketHeader({
    required this.type,
    required this.destConnectionId,
    required this.packetNumber,
  });

  factory PacketHeader.fromBytes(List<int> bytes) {
    int _typeInt = buildBytes32(bytes, 0);
    int destConnectionId = buildBytes32(bytes, 4);
    int packetNumber = buildBytes32(bytes, 8);
    PacketType type = PacketType.invalid;
    if(_typeInt >= 0 && _typeInt < PacketType.values.length) {
      type = PacketType.values[_typeInt];
    }
    return PacketHeader(type: type, destConnectionId: destConnectionId, packetNumber: packetNumber);
  }

  void fillBytes(List<int> list) {
    if(list.length < getLength()) {
      return;
    }
    fillBytes32(list, 0, type.index);
    fillBytes32(list, 4, destConnectionId);
    fillBytes32(list, 8, packetNumber);
  }

  static int getLength() {
    return 12;
  }
}

/// Abstract class for sending and resending packets
abstract class Packet {
  PacketHeader header;

  Packet({required this.header});

  PacketType getType() {
    return header.type;
  }

  void setPacketNumber(int number) {
    header.packetNumber = number;
  }

  int getPacketNumber() {
    return header.packetNumber;
  }

  List<int> toBytes();
}

/// Packet implementation for connect/connect_ack/connected message
class PacketConnect extends Packet {
  int sourceConnectionId;

  PacketConnect({
    required super.header,
    required this.sourceConnectionId,
  });

  factory PacketConnect.fromBytes(List<int> bytes) {
    var header = PacketHeader.fromBytes(bytes);
    var connectionId = buildBytes32(bytes, PacketHeader.getLength());
    return PacketConnect(sourceConnectionId: connectionId, header: header);
  }

  @override
  List<int> toBytes() {
    var result = List.filled(getLength(), 0);
    header.fillBytes(result);
    fillBytes32(result, PacketHeader.getLength(), sourceConnectionId);
    return result;
  }

  static int getLength() {
    return PacketHeader.getLength() + 4;
  }
}

/// Packet implementation for data message
class PacketData extends Packet {
  List<Frame> frames;

  PacketData({
    required this.frames,
    required super.header,
  });

  factory PacketData.fromBytes(List<int> bytes) {
    var header = PacketHeader.fromBytes(bytes);
    final data = bytes.sublist(PacketHeader.getLength());
    var parser = FrameParser(data: data);
    final frames = parser.parse();
    return PacketData(frames: frames, header: header);
  }

  @override
  List<int> toBytes() {
    var result = List.filled(getLength(), 0);
    header.fillBytes(result);
    int t = PacketHeader.getLength();
    for(var frame in frames) {
      var bytes = frame.toBytes();
      final len = bytes.length;
      result.setRange(t, t + len, bytes);
      t += len;
    }
    return result;
  }

  int getLength() {
    int result = PacketHeader.getLength();
    for(var frame in frames) {
      result += frame.getLength();
    }
    return result;
  }
}

/// Packet implementation for hello message
/// +---------------+
/// | header        |
/// +---------------+
/// | len(2)        |
/// +---------------+
/// | deviceId(len) |
/// +---------------+
class PacketAnnounce extends Packet {
  String deviceId;

  PacketAnnounce({
    required this.deviceId,
    required super.header,
  });

  factory PacketAnnounce.fromBytes(List<int> bytes) {
    var header = PacketHeader.fromBytes(bytes);
    int len = buildBytes16(bytes, PacketHeader.getLength());
    final data = bytes.sublist(PacketHeader.getLength() + 2);
    if(data.length != len) {
      //TODO invalid frame
    }
    String deviceId = utf8.decode(data);
    return PacketAnnounce(header: header, deviceId: deviceId);
  }

  @override
  List<int> toBytes() {
    var result = List.filled(getLength(), 0);
    header.fillBytes(result);
    int len = deviceId.length;
    int start = PacketHeader.getLength();
    fillBytes16(result, start, len);
    start += 2;
    var bytes = utf8.encode(deviceId);
    result.setRange(start, start + len, bytes);
    return result;
  }

  int getLength() {
    int headerLength = PacketHeader.getLength();
    int len = deviceId.length;
    return headerLength + len + 2;
  }

  static bool isValid(List<int> data) {
    int headerLength = PacketHeader.getLength();
    int len = buildBytes16(data, headerLength);
    return data.length == headerLength + 2 + len;
  }
}

class PacketFactory {
  List<int> data;
  int _type;

  PacketFactory({required this.data}): _type = buildBytes32(data, 0);

  /// Check whether packet data is valid, based on the packet type and data length
  bool isValid() {
    if(_type < 0 || _type >= PacketType.values.length) {
      return false;
    }
    var packetType = PacketType.values[_type];
    int length = data.length;
    switch(packetType) {
      case PacketType.connect:
      case PacketType.connectAck:
      case PacketType.connected:
        return length == PacketConnect.getLength();
      case PacketType.data:
        return true;
      case PacketType.announce:
        return PacketAnnounce.isValid(data);
      case PacketType.invalid:
        return false;
    }
  }

  PacketType getType() {
    if(!isValid()) {
      return PacketType.invalid;
    }
    return PacketType.values[_type];
  }

  PacketConnect getPacketConnect() {
    return PacketConnect.fromBytes(data);
  }

  PacketData getPacketData() {
    return PacketData.fromBytes(data);
  }

  PacketAnnounce getPacketHello() {
    return PacketAnnounce.fromBytes(data);
  }

  Packet? getAbstractPacket() {
    final type = getType();
    switch(type) {
      case PacketType.connect:
      case PacketType.connectAck:
      case PacketType.connected:
        return getPacketConnect();
      case PacketType.data:
        return getPacketData();
      case PacketType.announce:
        return getPacketHello();
      case PacketType.invalid:
        return null;
    }
  }
}