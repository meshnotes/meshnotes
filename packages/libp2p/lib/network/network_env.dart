import 'dart:io';

import 'protocol/packet.dart';

class NetworkEnvSimulator {
  int Function(RawDatagramSocket socket, InternetAddress ip, int port, Packet packet) sendHook;

  NetworkEnvSimulator({required this.sendHook});

  static NetworkEnvSimulator dropAll = NetworkEnvSimulator(sendHook: dropAllHook);
  static NetworkEnvSimulator acceptAll = NetworkEnvSimulator(sendHook: acceptAllHook);

  static int dropAllHook(RawDatagramSocket socket, InternetAddress ip, int port, Packet packet) {
    return 0;
  }
  static int acceptAllHook(RawDatagramSocket socket, InternetAddress ip, int port, Packet packet) {
    return socket.send(packet.toBytes(), ip, port);
  }
}