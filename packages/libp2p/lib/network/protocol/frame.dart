import 'util.dart';

enum FrameType {
  dataFrame,
  ackFrame,
  heartbeatFrame,
  invalidFrame,
}

abstract class Frame {
  FrameType type;

  Frame({
    required this.type,
  });
  List<int> toBytes();
  int getLength() {
    return 1;
  }
}

class FrameData extends Frame {
  int objId;
  int seqNum;
  int total;
  List<int> data;

  FrameData({
    required this.objId,
    required this.seqNum,
    required this.total,
    required this.data,
  }): super(type: FrameType.dataFrame);

  factory FrameData.fromBytes(List<int> raw, int start) {
    final objId = buildBytes32(raw, start);
    start += 4;
    final sequenceNumber = buildBytes32(raw, start);
    start += 4;
    final total = buildBytes32(raw, start);
    start += 4;
    final length = buildBytes16(raw, start);
    start += 2;
    final data = raw.sublist(start, start + length);
    return FrameData(
      objId: objId,
      seqNum: sequenceNumber,
      total: total,
      data: data,
    );
  }

  @override
  List<int> toBytes() {
    var result = List.filled(getLength(), 0);
    int start = 0;
    fillBytes8(result, start, type.index);
    start++;
    fillBytes32(result, start, objId);
    start += 4;
    fillBytes32(result, start, seqNum);
    start += 4;
    fillBytes32(result, start, total);
    start += 4;
    fillBytes16(result, start, data.length);
    start += 2;
    for(int i = 0; i < data.length; i++) {
      fillBytes8(result, start++, data[i]);
    }
    return result;
  }

  @override
  int getLength() {
    return super.getLength() // type length
        + 4 // objId length
        + 4 // seqNum length
        + 4 // total length
        + 2 // length length
        + data.length; // data length
  }
}

class FrameAck extends Frame {
  int packetNumber;
  int objId;
  int seqNum;

  FrameAck({
    required this.packetNumber,
    required this.objId,
    required this.seqNum,
  }): super(type: FrameType.ackFrame);

  factory FrameAck.fromBytes(List<int> raw, int start) {
    final packetNumber = buildBytes32(raw, start);
    start += 4;
    final objId = buildBytes32(raw, start);
    start += 4;
    final seqNum = buildBytes32(raw, start);
    start += 4;
    return FrameAck(
      packetNumber: packetNumber,
      objId: objId,
      seqNum: seqNum,
    );
  }

  @override
  List<int> toBytes() {
    var result = List.filled(getLength(), 0);
    int start = 0;
    fillBytes8(result, start, type.index);
    start++;
    fillBytes32(result, start, packetNumber);
    start += 4;
    fillBytes32(result, start, objId);
    start += 4;
    fillBytes32(result, start, seqNum);
    return result;
  }

  @override
  int getLength() {
    return super.getLength() // type length
        + 4 // packetNumber length
        + 4 // objId length
        + 4; // seqNum length
  }
}

class FrameHeartbeat extends Frame {
  static const int tagRequest = 0;
  static const int tagResponse = 1;
  int data;

  FrameHeartbeat({
    required this.data,
  }): super(type: FrameType.heartbeatFrame);

  factory FrameHeartbeat.request() {
    return FrameHeartbeat(data: tagRequest);
  }
  factory FrameHeartbeat.response() {
    return FrameHeartbeat(data: tagResponse);
  }
  factory FrameHeartbeat.fromBytes(List<int> raw, int start) {
    final data = buildBytes8(raw, start);
    start += 1;
    return FrameHeartbeat(
      data: data,
    );
  }

  @override
  List<int> toBytes() {
    var result = List.filled(getLength(), 0);
    int start = 0;
    fillBytes8(result, start, type.index);
    start++;
    fillBytes8(result, start, data);
    start += 1;
    return result;
  }

  @override
  int getLength() {
    return super.getLength() // type length
        + 1; // data length
  }

  bool isRequest() {
    return data == tagRequest;
  }
}

class FrameInvalid extends Frame {
  FrameInvalid():super(type: FrameType.invalidFrame);

  @override
  List<int> toBytes() {
    return [];
  }
}

class FrameParser {
  List<int> data;
  FrameParser({
    required this.data,
  });

  List<Frame> parse() {
    var result = <Frame>[];
    int t = 0;
    while(t < data.length - 1) {
      int type = buildBytes8(data, t);
      t++;
      if(type < 0 || type >= FrameType.values.length) {
        // TODO 这里要添加日志
        result.add(FrameInvalid());
        break;
      }
      final frameType = FrameType.values[type];
      var frame = parseType(frameType, data, t);
      result.add(frame);
      // 只要遇到了无效Frame，就不再解析后面的
      if(frame.type == FrameType.invalidFrame) {
        break;
      }
      t += frame.getLength() - 1;
    }
    return result;
  }

  Frame parseType(FrameType type, List<int> data, int start) {
    switch(type) {
      case FrameType.dataFrame:
        return _buildFrameData(data, start);
      case FrameType.ackFrame:
        return _buildFrameAck(data, start);
      case FrameType.heartbeatFrame:
        return _buildHeartbeat(data, start);
      case FrameType.invalidFrame:
        return FrameInvalid();
    }
  }

  Frame _buildFrameData(List<int> data, int start) {
    return FrameData.fromBytes(data, start);
  }

  Frame _buildFrameAck(List<int> data, int start) {
    return FrameAck.fromBytes(data, start);
  }

  Frame _buildHeartbeat(List<int> data, int start) {
    return FrameHeartbeat.fromBytes(data, start);
  }
}