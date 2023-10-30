import 'package:libp2p/libp2p.dart';

void main(List<String> args) async {
  if(args.length != 1) {
    print('Usage: server <port>');
    return;
  }
  int port = int.tryParse(args[0])?? -1;
  if(port == -1) {
    print('Invalid argument <port>: ${args[0]}');
    return;
  }
  var _ = await startListening(port);
}
