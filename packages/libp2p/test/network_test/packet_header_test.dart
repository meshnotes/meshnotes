import 'package:my_log/my_log.dart';
import 'package:test/test.dart';
import 'package:libp2p/network/protocol/packet.dart';

void main() {
  test('PacketHeader fill bytes', () {
    MyLogger.initForTest(name: 'libp2p_test');
    var expectedResult = [0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3];
    var header = PacketHeader(type: PacketType.values[1], destConnectionId: 2, packetNumber: 3);
    var result = List.filled(PacketHeader.getLength(), 0);
    header.fillBytes(result);
    expect(result.length, expectedResult.length);
    for(int i = 0; i < result.length; i++) {
      expect(result[i], expectedResult[i]);
    }
  });

  test('PacketHeader from bytes', () {
    MyLogger.initForTest(name: 'libp2p_test');
    var expectedResult = PacketHeader(type: PacketType.values[2], destConnectionId: 0x01000000, packetNumber: 0x020000);
    var bytes = [0x00, 0x00, 0x00, 0x02, 0x01, 0, 0, 0, 0, 0x02, 0, 0];
    var result = PacketHeader.fromBytes(bytes);
    expect(result.type, expectedResult.type);
    expect(result.destConnectionId, expectedResult.destConnectionId);
    expect(result.packetNumber, expectedResult.packetNumber);
  });
}