import 'dart:io';

import 'package:args/args.dart';
import 'package:keygen/keygen.dart';
import 'package:libp2p/application/application_api.dart';
import 'package:libp2p/dal/village_db.dart';
import 'package:libp2p/overlay/overlay_layer.dart';
import 'package:libp2p/overlay/villager_node.dart';
import 'package:my_log/my_log.dart';
import 'package:server/relay_application.dart';
import 'package:server/server_db.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

void main(List<String> args) async {
  MyLogger.initForConsoleTest(name: 'server', debug: true);
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', help: 'Show this help message', negatable: false)
    ..addFlag('gen-key', abbr: 'g', help: 'Generate a new private key and save to config', negatable: false)
    ..addOption('port', abbr: 'p', help: 'Port to listen on')
    ..addOption('dir', abbr: 'd', help: 'Directory to store server data', defaultsTo: './server_data');

  final argResults = parser.parse(args);

  if(argResults['help']) {
    print(parser.usage);
    return;
  }

  final dataDir = argResults['dir'] as String;
  final configPath = p.join(dataDir, 'server_config.yaml');

  if(argResults['gen-key']) {
    await _generateKey(dataDir, configPath);
    return;
  }

  final portStr = argResults['port'] as String?;
  if(portStr == null) {
    print(parser.usage);
    return;
  }

  final port = int.tryParse(portStr) ?? -1;
  if(port == -1) {
    print('Invalid port: $portStr');
    return;
  }

  await _startServer(port, dataDir, configPath);
}

Future<void> _generateKey(String dataDir, String configPath) async {
  final dir = Directory(dataDir);
  if(!await dir.exists()) {
    await dir.create(recursive: true);
  }

  final wrapper = SigningWrapper.random();
  final privateKey = wrapper.getPrivateKey();
  final publicKey = wrapper.getCompressedPublicKey();

  final config = {
    'private_key': privateKey,
    'public_key': publicKey,
    'device_id': 'server_${DateTime.now().millisecondsSinceEpoch}',
    'user_name': 'relay_server',
  };

  final file = File(configPath);
  final yamlString = YamlWriter().write(config);
  await file.writeAsString(yamlString, mode: FileMode.write);
  print('Successfully generated keys and saved to $configPath');
}

Future<void> _startServer(int port, String dataDir, String configPath) async {
  final configFile = File(configPath);
  if(!await configFile.exists()) {
    print('Config file not found at $configPath. Please run with --gen-key first.');
    return;
  }

  final yamlString = await configFile.readAsString();
  final configYaml = loadYaml(yamlString);
  final deviceId = configYaml['device_id'] as String;
  final publicKey = configYaml['public_key'] as String;
  final userName = configYaml['user_name'] as String;
  final privateKey = configYaml['private_key'] as String;
  final signing = SigningWrapper.loadKey(privateKey);
  if(signing.getCompressedPublicKey() != publicKey) {
    print('Config public_key does not match private_key. Please regenerate server_config.yaml.');
    return;
  }

  final userInfo = UserPublicInfo(
    publicKey: publicKey,
    userName: userName,
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );

  // Initialize DB
  final db = VillageDbHelper();
  await db.init(dataDir); // Initialize with data directory

  final serverDb = ServerDbHelper();
  await serverDb.init(dataDir);
  final activeConnections = <String>{};

  final overlay = VillageOverlay(
    userInfo: userInfo,
    sponsors: [],
    port: port,
    deviceId: deviceId,
    useMulticast: false,
    allowSendingToPublicServer: true,
    onNodeChanged: (node) {
      MyLogger.info('Node changed: ${node.nodeId}, status: ${node.getStatus()}');
      final connectionKey = '${node.ip?.address ?? node.host}:${node.port}';
      if(node.getStatus() == VillagerStatus.keepInTouch && activeConnections.add(connectionKey)) {
        MyLogger.info('Server accepted connection: $connectionKey, nodeId=${node.nodeId}');
      } else if(node.getStatus() == VillagerStatus.lostContact && activeConnections.remove(connectionKey)) {
        MyLogger.info('Server connection closed: $connectionKey, nodeId=${node.nodeId}');
      }
      final ip = node.ip?.address ?? '';
      serverDb.upsertClient(node.nodeId, node.publicKey, ip, node.port, DateTime.now().millisecondsSinceEpoch);
    },
  );

  final relayApp = RelayApplication(
    overlay: overlay,
    db: db,
    serverDb: serverDb,
    signing: signing,
    upperAppName: 'mesh_notes',
  );

  await relayApp.start();
  print('Relay server started on port $port with deviceId $deviceId');
}
