import 'package:test/test.dart';
import 'package:keygen/keygen.dart';

void main() {
  test('Test hashing binary', () {
    List<int> bytes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    final result = HashUtil.hashBytes(bytes);
    print('result=$result');
    expect(result, '78a6273103d17c39a0b6126e226cec70e33337f4bc6a38067401b54a33e78ead');
  });

  test('Test hashing text', () {
    String text = 'Simple text';
    final result = HashUtil.hashText(text);
    print('result=$result');
    expect(result, '77f1b6fb3434e4be5067ea261e2edc7f2256d527ace31a2f26e168394367c4da');
  });
}