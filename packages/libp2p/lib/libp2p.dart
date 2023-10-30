library libp2p;

import 'dart:convert';
import 'dart:io';

import 'network/network_layer.dart';

Future<SOTPNetworkLayer> startListening(int bindPort) async {
  var network = SOTPNetworkLayer(localIp: InternetAddress.anyIPv4, localPort: bindPort, connectOkCallback: (c) {
    print('Connection established to ${c.ip}:${c.port} with source connection Id ${c.getSourceId()} and dest connection Id ${c.getDestinationId()}');
  });
  print('Start listening on port ${network.localPort}');
  await network.start();
  return network;
  // return connection;
  // RawDatagramSocket rawDgramSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, binedPort);
  //
  // print('Server started');
  // await for (RawSocketEvent event in rawDgramSocket) {
  //   if(event == RawSocketEvent.read) {
  //     var recv = rawDgramSocket.receive()!;
  //     var data = utf8.decode(recv.data);
  //     var ip = recv.address.address;
  //     var port = recv.port;
  //     print('Receive ${recv.data.length} bytes from $ip:$port: $data');
  //     sendAck(rawDgramSocket, ip, port);
  //   } else {
  //     print('Receive event: $event');
  //   }
  // }
}

void sendAck(RawDatagramSocket udp, String ip, int port) {
  udp.send(utf8.encode('ack'), InternetAddress(ip), port);
}