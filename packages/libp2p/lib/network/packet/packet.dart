import 'frame.dart';
import 'util.dart';

enum PacketType {
  connect,
  connectAck,
  connected,
  data,
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

// Abstract class for sending and resending packets
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

// Packet implementation for connect/connect_ack/connected message
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

// Packet implementation for data message
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

class PacketFactory {
  List<int> data;
  int _type;

  PacketFactory({required this.data}): _type = buildBytes32(data, 0);

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

  Packet? getAbstractPacket() {
    final type = getType();
    switch(type) {
      case PacketType.connect:
      case PacketType.connectAck:
      case PacketType.connected:
        return getPacketConnect();
      case PacketType.data:
        return getPacketData();
      case PacketType.invalid:
        return null;
    }
  }
}