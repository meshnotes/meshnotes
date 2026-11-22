import 'dart:math';

class TransactionUtil {
  static const int transactionIdLength = 16;

  static final Random _transactionRandom = Random.secure();

  static String generateTransactionId() {
    return List.generate(transactionIdLength, (_) => _transactionRandom.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}