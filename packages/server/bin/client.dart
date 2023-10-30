import 'package:libp2p/libp2p.dart';

void main(List<String> args) async {
  // String server = '106.53.92.146';
  String server = '127.0.0.1';
  await startUDPClient(server, 8081);
}

startUDPClient(String serverIp, int serverPort) async {
  var connection = await startListening(0);
  connection.connect(serverIp, serverPort);

  int n = 1500;
  String msg = '';
  for(int i = 0; i < n; i++) {
    msg = msg + (i % 10).toString();
  }
  //
  // print('Client send ${msg.length} bytes');
  // connection.sendMsg(msg, serverIp, serverPort);
}