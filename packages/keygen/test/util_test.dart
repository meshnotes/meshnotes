import 'package:test/test.dart';
import 'package:keygen/src/util.dart';

void main() {
  test('Test converting bytes to hex string', () {
    List<int> bytes = [0x01, 0x23, 0x45, 0x67,0x89, 0xAB, 0xCD, 0xEF];
    final result = bytes2Hex(bytes);
    print('result=$result');
    expect(result, '0123456789abcdef');
  });
}