import 'package:my_log/my_log.dart';
import 'package:test/test.dart';
import 'package:libp2p/network/protocol/packet.dart';

void main() {
  test('Packet from bytes', () {
    MyLogger.initForTest(name: 'libp2p_test');
    var bytes = [0, 0, 0, PacketType.connected.index, 0x11, 0x22, 0x33, 0x44, 0, 0, 0, 5, 0, 0, 0, 6];
    var packet = PacketFactory(data: bytes);
    expect(packet.isValid(), true);
    expect(packet.getType(), PacketType.connected);
  });

  test('Insufficient bytes data', () {
    MyLogger.initForTest(name: 'libp2p_test');
    var bytesNotEnough = [0, 1];
    var packet = PacketFactory(data: bytesNotEnough);
    expect(packet.getType(), PacketType.invalid);
    expect(packet.isValid(), false);
  });

  test('type out of range', () {
    MyLogger.initForTest(name: 'libp2p_test');
    var bytes = [0, 0, 0xff, 0xff, 0, 0, 0, 1, 0, 0, 0, 2, 0, 0, 0, 3];
    var packet = PacketFactory(data: bytes);
    expect(packet.isValid(), false);
    expect(packet.getType(), PacketType.invalid);
  });
}
