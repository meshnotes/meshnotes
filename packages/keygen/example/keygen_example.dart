import 'package:keygen/keygen.dart';

void main() {
  final rsa = SigningWrapper.random();
  print('new key: ${rsa.getPublicKey()}');
}
