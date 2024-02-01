import 'package:my_log/my_log.dart';
import 'package:test/test.dart';
import 'package:libp2p/network/protocol/packet.dart';

void main() {
  test('PacketConnect to bytes', () {
    MyLogger.initForTest(name: 'libp2p_test');
    var expectedResult = [0, 0, 0, PacketType.connect.index, 0x34, 0x56, 0x78, 0x90, 0, 0, 0, 123, 0x12, 0x34, 0x56, 0x78];
    var packet = PacketConnect(sourceConnectionId: 0x12345678, header: PacketHeader(type: PacketType.connect, destConnectionId: 0x34567890, packetNumber: 123));
    var result = packet.toBytes();
    expect(result.length, expectedResult.length);
    for(int i = 0; i < result.length; i++) {
      expect(result[i], expectedResult[i]);
    }
  });

  test('PacketConnect from bytes', () {
    MyLogger.initForTest(name: 'libp2p_test');
    var expectedResult = PacketConnect(
      header: PacketHeader(type: PacketType.connectAck, destConnectionId: 0x10203040, packetNumber: 0x456789),
      sourceConnectionId: 0xa0b0c0d0,
    );
    var bytes = [0, 0, 0, PacketType.connectAck.index, 0x10, 0x20, 0x30, 0x40, 0, 0x45, 0x67, 0x89, 0xa0, 0xb0, 0xc0, 0xd0];
    var result = PacketConnect.fromBytes(bytes);
    expect(result.header.type, expectedResult.header.type);
    expect(result.header.destConnectionId, expectedResult.header.destConnectionId);
    expect(result.header.packetNumber, expectedResult.header.packetNumber);
    expect(result.sourceConnectionId, expectedResult.sourceConnectionId);
  });
}