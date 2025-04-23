import 'dart:math';

final _random = Random.secure();
const minimalInitialPacketNumber = 10;
const maximumInitialPacketNumber = 4096;

int randomInt(int min, int max) {
  return _random.nextInt(max - min) + min;
}

int randomId() {
  return randomInt(1, 1<<32);
}

int randomInitialPacketNumber() {
  return _random.nextInt(maximumInitialPacketNumber - minimalInitialPacketNumber) + minimalInitialPacketNumber;
}

int networkNow() {
  return DateTime.now().millisecondsSinceEpoch;
}