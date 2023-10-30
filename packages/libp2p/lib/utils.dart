import 'dart:math';

final _random = Random.secure();
const minimalInitialPacketNumber = 10;
const maximumInitialPacketNumber = 1000;

int randomId() {
  return _random.nextInt(1<<32);
}

int randomInitialPacketNumber() {
  return _random.nextInt(maximumInitialPacketNumber - minimalInitialPacketNumber) + minimalInitialPacketNumber;
}