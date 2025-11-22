# Mesh Notes - Network Protocol Design

## Overview

Mesh Notes uses a custom P2P protocol built on UDP with a reliability layer. The stack has three layers: network, overlay, and application.

## Protocol Stack

```
┌─────────────────────────────────┐
│   Application Layer (Village)   │  Application: version sync, resource exchange
├─────────────────────────────────┤
│   Overlay Layer (VillageOverlay)│  Overlay: node discovery, connection mgmt
├─────────────────────────────────┤
│   Network Layer (SOTP)          │  Network: reliable transport, packets
├─────────────────────────────────┤
│   UDP Sockets                   │  Transport: raw UDP packets
└─────────────────────────────────┘
```

**Location**: [packages/libp2p/lib/](../packages/libp2p/lib/)

## Network Layer (SOTP)

### Packet structure

**Location**: [packages/libp2p/lib/network/protocol/packet.dart](../packages/libp2p/lib/network/protocol/packet.dart)

#### PacketHeader

```dart
class PacketHeader {
  PacketType type;          // Packet type (4 bytes)
  int destConnectionId;     // Destination connection ID (4 bytes)
  int packetNumber;         // Packet sequence (4 bytes)
}
```

**Total size**: 12 bytes

#### PacketType

```dart
enum PacketType {
  connect,      // 0: connect request
  connectAck,   // 1: connect ack
  connected,    // 2: connection established
  data,         // 3: data
  announce,     // 4: LAN announce
  announceAck,  // 5: announce ack
  bye,          // 6: close connection
}
```

### Packet types

#### 1. PacketConnect

```dart
class PacketConnect extends Packet {
  int sourceConnectionId;   // Source connection ID
}
```

**Flow**:
```
A → B: PacketConnect(sourceConnectionId=123)
B → A: PacketConnectAck(destConnectionId=123, sourceConnectionId=456)
A → B: PacketConnected(destConnectionId=456)
```

#### 2. PacketConnectAck

```dart
class PacketConnectAck extends Packet {
  int sourceConnectionId;   // Source connection ID
}
```

#### 3. PacketConnected

```dart
class PacketConnected extends Packet {
  // no extra fields
}
```

After this, both sides can send data packets.

#### 4. PacketData

```dart
class PacketData extends Packet {
  List<Frame> frames;       // Frame list
}
```

**Frame structure**:
```dart
class Frame {
  int id;                   // Frame ID (2 bytes)
  bool isEnd;               // Last frame flag (1 bit)
  Uint8List data;           // Payload (variable)
}
```

**Large payloads**:
- Split data into multiple frames
- Max frame size 1400 bytes
- Reassemble via `id` and `isEnd`

#### 5. PacketAnnounce

```dart
class PacketAnnounce extends Packet {
  String ip;                // IP address
  int port;                 // Port
  String deviceId;          // Device ID
}
```

**Purpose**:
- Broadcast presence on LAN
- Auto-discover peers
- Uses Bonjour/mDNS

#### 6. PacketAnnounceAck

```dart
class PacketAnnounceAck extends Packet {
  String ip;                // IP address
  int port;                 // Port
  String deviceId;          // Device ID
}
```

#### 7. PacketBye

```dart
class PacketBye extends Packet {
  String tag;               // Reason tag
}
```

**Reasons**:
- `"user"`: user initiated
- `"timeout"`: timeout
- `"error"`: error

### Reliability

**Location**: [packages/libp2p/lib/network/protocol/sotp_network_layer.dart](../packages/libp2p/lib/network/protocol/sotp_network_layer.dart)

#### Connection management

```dart
class Connection {
  int connectionId;         // Connection ID
  InternetAddress address;  // Remote address
  int port;                 // Remote port
  ConnectionStatus status;  // Status
  int lastPacketNumber;     // Last sequence number
  Timer? keepAliveTimer;    // Keep-alive timer
}

enum ConnectionStatus {
  connecting,
  connected,
  closed,
}
```

#### Packet numbers

Every packet has a unique sequence used for:
- Loss detection
- Retransmission
- Ordering

```dart
int _nextPacketNumber = 0;

void sendPacket(Packet packet) {
  packet.header.packetNumber = _nextPacketNumber++;
  _socket.send(packet.encode(), address, port);
}
```

#### Keep-alive

```dart
Timer.periodic(Duration(seconds: 5), (timer) {
  for (var conn in _connections.values) {
    if (conn.isConnected) {
      // Send empty payload as heartbeat
      sendData(conn.connectionId, Uint8List(0));
    }
  }
});
```

## Overlay Layer

**Location**: [packages/libp2p/lib/overlay/overlay_layer.dart](../packages/libp2p/lib/overlay/overlay_layer.dart)

### Node model

#### VillagerNode

```dart
class VillagerNode {
  String id;                // Node ID (public key)
  InternetAddress? address; // IP address
  int? port;                // Port
  VillagerStatus status;    // Node status
  Peer? peer;               // Underlying connection
  DateTime lastSeen;        // Last active time
}

enum VillagerStatus {
  unknown,
  resolved,
  keepInTouch,
  lostContact,
}
```

### Node discovery

#### 1. LAN discovery (mDNS/Bonjour)

```dart
class BonjourDiscovery {
  void startAdvertising() {
    // Broadcast our service
    _service = BonsoirService(
      name: _deviceId,
      type: '_meshnotes._udp',
      port: _port,
    );
    _service.start();
  }

  void startDiscovery() {
    // Listen for other services
    _discovery = BonsoirDiscovery(type: '_meshnotes._udp');
    _discovery.listen((event) {
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
        _onServiceFound(event.service);
      }
    });
  }
}
```

#### 2. Manual peers (Sponsor)

```dart
class SponsorManager {
  List<Sponsor> sponsors = [];  // Manually configured peers

  void addSponsor(String ip, int port) {
    sponsors.add(Sponsor(ip: ip, port: port));
  }

  void connectToSponsors() {
    for (var sponsor in sponsors) {
      _overlay.connectTo(sponsor.ip, sponsor.port);
    }
  }
}
```

### Connection management

#### Hello message

Peers send Hello after connecting to introduce themselves:

```dart
class HelloMessage {
  String deviceId;          // Device ID
  String publicKey;         // Public key
  String deviceName;        // Device name
  String version;           // Protocol version
}
```

#### Health check

```dart
Timer.periodic(Duration(seconds: 5), (timer) {
  for (var node in _nodes.values) {
    if (node.status == VillagerStatus.keepInTouch) {
      final timeSinceLastSeen = DateTime.now().difference(node.lastSeen);
      if (timeSinceLastSeen > Duration(seconds: 30)) {
        node.status = VillagerStatus.lostContact;
        _attemptReconnect(node);
      }
    }
  }
});
```

#### Reconnect

```dart
void _attemptReconnect(VillagerNode node) {
  if (node.address != null && node.port != null) {
    final peer = _networkLayer.connect(node.address!, node.port!);
    if (peer != null) {
      node.peer = peer;
      node.status = VillagerStatus.keepInTouch;
      _sendHello(node);
    }
  }
}
```

## Application Layer

**Location**: [packages/libp2p/lib/application/village.dart](../packages/libp2p/lib/application/village.dart)

### Message types

```dart
enum AppMessageType {
  provideAppType,   // 0: provide resources
  queryAppType,     // 1: query resources
  publishAppType,   // 2: publish message
}
```

#### 1. Provide

Respond to queries with requested resources:

```dart
class ProvideMessage {
  AppMessageType type = AppMessageType.provideAppType;
  List<Resource> resources;
}

class Resource {
  String id;                // Resource ID (hash)
  Uint8List data;           // Content
}
```

#### 2. Query

Request specific resources:

```dart
class QueryMessage {
  AppMessageType type = AppMessageType.queryAppType;
  List<String> resourceIds; // Requested resource IDs
}
```

#### 3. Publish

Broadcast a message to all peers:

```dart
class PublishMessage {
  AppMessageType type = AppMessageType.publishAppType;
  String topic;             // Topic
  Uint8List data;           // Payload
}
```

### Version sync protocol

**Location**: [lib/net/net_isolate.dart](../lib/net/net_isolate.dart)

#### Message format

All messages are signed and encrypted:

```dart
class SignedMessage {
  String userPublicId;      // Sender public key
  String data;              // Payload (JSON)
  String signature;         // signature = sign(hash(data))
}
```

**Verification**:
```dart
bool verify(SignedMessage msg) {
  final hash = HashUtil.hashText(msg.data);
  return VerifyingWrapper(msg.userPublicId).verify(hash, msg.signature);
}
```

#### Resource format

```dart
class SignedResources {
  String userPublicId;
  List<SignedResource> resources;
  String signature;         // signature = sign(hash(resources))
}

class SignedResource {
  String id;                // Resource ID (hash)
  String encryptedContent;  // Encrypted payload = encrypt(timestamp + content)
}
```

**Encryption flow**:
```dart
String encrypt(int timestamp, String content) {
  final plaintext = '$timestamp\n$content';
  return EncryptWrapper(key).encrypt(timestamp, plaintext);
}
```

#### Sync flow

**1. Version broadcast**:

```dart
// Broadcast version hash every 30s
Timer.periodic(Duration(seconds: 30), (timer) {
  final currentVersionHash = _getCurrentVersionHash();
  _village.publish('version-hash', currentVersionHash);
});
```

**2. Version request**:

```dart
// When receiving a version hash
void onVersionHashReceived(String remoteHash) {
  if (remoteHash != _getCurrentVersionHash()) {
    // Mismatch -> request full version tree
    _village.query(['version-tree:$remoteHash']);
  }
}
```

**3. Version transfer**:

```dart
// Respond to version tree request
void onVersionTreeQuery(String hash) {
  final versionTree = _getVersionTree(hash);
  final objects = _getRequiredObjects(versionTree);

  // Send version tree
  _village.provide([
    Resource(id: 'version-tree:$hash', data: versionTree.encode()),
  ]);

  // Send related objects
  for (var obj in objects) {
    _village.provide([
      Resource(id: obj.hash, data: obj.content),
    ]);
  }
}
```

**4. Object request**:

```dart
// Version tree lists object hashes
void onVersionTreeReceived(VersionTree tree) {
  final missingObjects = _findMissingObjects(tree);

  if (missingObjects.isNotEmpty) {
    // Batch request missing objects
    _village.query(missingObjects);
  }
}
```

**5. Merge**:

```dart
// After all objects arrive, merge
void onAllObjectsReceived() {
  _mergeTaskQueue.add(MergeTask(
    remoteVersionHash: remoteHash,
    remoteVersionTree: versionTree,
  ));
}
```

## Encryption and Security

**Location**: [packages/keygen/lib/](../packages/keygen/lib/)

### Keys

#### 1. Signing (Ed25519)

```dart
class SigningWrapper {
  final SigningKey _key;    // Private key

  String sign(String hash) {
    final signature = _key.sign(Uint8List.fromList(hash.codeUnits));
    return base64Encode(signature);
  }
}

class VerifyingWrapper {
  final VerifyKey _key;     // Public key

  bool verify(String hash, String signature) {
    final sig = base64Decode(signature);
    try {
      _key.verify(sig, Uint8List.fromList(hash.codeUnits));
      return true;
    } catch (e) {
      return false;
    }
  }
}
```

**Uses**:
- Message signatures
- Identity verification
- Tamper protection

#### 2. Encryption (AES)

```dart
class EncryptWrapper {
  final SecretBox _key;     // Symmetric key

  String encrypt(int timestamp, String content) {
    final nonce = _generateNonce(timestamp);
    final encrypted = _key.encrypt(
      Uint8List.fromList(content.codeUnits),
      nonce: nonce,
    );
    return base64Encode(encrypted.cipherText);
  }

  String decrypt(int timestamp, String encryptedContent) {
    final nonce = _generateNonce(timestamp);
    final decrypted = _key.decrypt(
      SecretBox(
        base64Decode(encryptedContent),
        nonce: nonce,
        mac: Mac.empty,
      ),
    );
    return String.fromCharCodes(decrypted);
  }
}
```

**Uses**:
- Content encryption
- Data confidentiality

### Security flows

#### User registration

```dart
void createUser(String username, String password) {
  // 1. Generate key pair
  final signingKey = SigningKey.generate();
  final publicKey = signingKey.verifyKey;

  // 2. Generate encryption key
  final encryptKey = SecretBox.randomKey();

  // 3. Encrypt private keys with password
  final encryptedSigningKey = _encryptWithPassword(signingKey, password);
  final encryptedEncryptKey = _encryptWithPassword(encryptKey, password);

  // 4. Persist
  _db.saveUser(
    username: username,
    publicKey: publicKey,
    encryptedSigningKey: encryptedSigningKey,
    encryptedEncryptKey: encryptedEncryptKey,
  );
}
```

#### User login

```dart
bool login(String username, String password) {
  // 1. Load from DB
  final user = _db.getUser(username);

  // 2. Decrypt private keys
  try {
    final signingKey = _decryptWithPassword(user.encryptedSigningKey, password);
    final encryptKey = _decryptWithPassword(user.encryptedEncryptKey, password);

    // 3. Load into memory (network Isolate)
    _loadKeys(signingKey, encryptKey);
    return true;
  } catch (e) {
    return false;  // wrong password
  }
}
```

#### Send message

```dart
void sendMessage(String message) {
  // 1. Serialize
  final data = jsonEncode(message);

  // 2. Hash
  final hash = HashUtil.hashText(data);

  // 3. Sign
  final signature = _signing.sign(hash);

  // 4. Build signed message
  final signedMessage = SignedMessage(
    userPublicId: _publicKey,
    data: data,
    signature: signature,
  );

  // 5. Publish
  _village.publish('message', signedMessage.encode());
}
```

#### Receive message

```dart
void onMessageReceived(SignedMessage msg) {
  // 1. Verify signature
  final hash = HashUtil.hashText(msg.data);
  final verifying = VerifyingWrapper(msg.userPublicId);
  if (!verifying.verify(hash, msg.signature)) {
    MyLogger.warn('Invalid signature');
    return;
  }

  // 2. Deserialize
  final message = jsonDecode(msg.data);

  // 3. Handle
  _handleMessage(message);
}
```

#### Send resource

```dart
void sendResource(String id, String content) {
  // 1. Encrypt content
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final encryptedContent = _encrypt.encrypt(timestamp, content);

  // 2. Build resource
  final resource = SignedResource(
    id: id,
    encryptedContent: encryptedContent,
  );

  // 3. Sign resource list
  final hash = HashUtil.hashText(jsonEncode([resource]));
  final signature = _signing.sign(hash);

  // 4. Send
  final signedResources = SignedResources(
    userPublicId: _publicKey,
    resources: [resource],
    signature: signature,
  );

  _village.provide(signedResources.encode());
}
```

#### Receive resource

```dart
void onResourceReceived(SignedResources res) {
  // 1. Verify signature
  final hash = HashUtil.hashText(jsonEncode(res.resources));
  final verifying = VerifyingWrapper(res.userPublicId);
  if (!verifying.verify(hash, res.signature)) {
    MyLogger.warn('Invalid signature');
    return;
  }

  // 2. Decrypt content
  for (var resource in res.resources) {
    final timestamp = _extractTimestamp(resource.encryptedContent);
    final content = _encrypt.decrypt(timestamp, resource.encryptedContent);

    // 3. Store
    _db.saveObject(resource.id, content);
  }
}
```

## Network Isolation

**Location**: [lib/net/net_isolate.dart](../lib/net/net_isolate.dart)

### Isolate architecture

```
┌─────────────────────────────────┐
│   Main Isolate                  │
│   - UI                          │
│   - DocumentManager             │
│   - Controller                  │
│                                 │
│   SendPort ↕ ReceivePort        │
└─────────────────────────────────┘
              ↕
┌─────────────────────────────────┐
│   Network Isolate               │
│   - VersionChainVillager        │
│   - Village (P2P)               │
│   - Signing/encrypt/decrypt     │
│   - Key management              │
│                                 │
│   ReceivePort ↕ SendPort        │
└─────────────────────────────────┘
```

### Message passing

#### Command

```dart
enum Command {
  start,                    // Start network
  stop,                     // Stop network
  sendVersionHash,          // Send version hash
  sendVersionTree,          // Send version tree
  sendObjects,              // Send objects
  queryObjects,             // Query objects
  addSponsor,               // Add manual peer
}
```

#### Main → Network

```dart
class NetworkController {
  SendPort? _networkSendPort;

  void sendVersionHash(String hash) {
    _networkSendPort?.send({
      'command': Command.sendVersionHash.index,
      'hash': hash,
    });
  }
}
```

#### Network → Main

```dart
class VersionChainVillager {
  SendPort _mainSendPort;

  void onVersionTreeReceived(VersionTree tree) {
    _mainSendPort.send({
      'event': 'versionTreeReceived',
      'hash': tree.hash,
      'tree': tree.encode(),
    });
  }
}
```

## Performance

### 1. Batch transfer

```dart
// Batch query objects
void queryObjects(List<String> ids) {
  const batchSize = 100;
  for (var i = 0; i < ids.length; i += batchSize) {
    final batch = ids.skip(i).take(batchSize).toList();
    _village.query(batch);
  }
}
```

### 2. Compression

```dart
// Compress large payloads
String compress(String content) {
  if (content.length > 1024) {
    return gzip.encode(content.codeUnits).toString();
  }
  return content;
}
```

### 3. Incremental sync

Send only changed objects:
```dart
List<String> findMissingObjects(VersionTree tree) {
  final missing = <String>[];
  for (var item in tree.table) {
    if (!_db.hasObject(item.docHash)) {
      missing.add(item.docHash);
    }
  }
  return missing;
}
```

### 4. Connection pool

```dart
class ConnectionPool {
  final int maxConnections = 10;
  List<Connection> _pool = [];

  Connection? getConnection(String nodeId) {
    // Reuse existing
    final existing = _pool.firstWhere(
      (conn) => conn.nodeId == nodeId,
      orElse: () => null,
    );
    if (existing != null) return existing;

    // If full, close least recently used
    if (_pool.length >= maxConnections) {
      _pool.sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
      _pool.first.close();
      _pool.removeAt(0);
    }

    // Create new connection
    final newConn = _createConnection(nodeId);
    _pool.add(newConn);
    return newConn;
  }
}
```

## Debugging and Monitoring

### Logging

```dart
class NetworkLogger {
  static void logPacketSent(Packet packet, InternetAddress addr, int port) {
    MyLogger.debug('SEND ${packet.type} to $addr:$port seq=${packet.header.packetNumber}');
  }

  static void logPacketReceived(Packet packet, InternetAddress addr, int port) {
    MyLogger.debug('RECV ${packet.type} from $addr:$port seq=${packet.header.packetNumber}');
  }
}
```

### Metrics

```dart
class NetworkStats {
  int packetsSent = 0;
  int packetsReceived = 0;
  int bytesSent = 0;
  int bytesReceived = 0;
  int connectionsActive = 0;
  int connectionsTotal = 0;

  Map<String, dynamic> toJson() {
    return {
      'packetsSent': packetsSent,
      'packetsReceived': packetsReceived,
      'bytesSent': bytesSent,
      'bytesReceived': bytesReceived,
      'connectionsActive': connectionsActive,
      'connectionsTotal': connectionsTotal,
    };
  }
}
```

## Known Limitations

1. **NAT traversal**: complex NAT not supported
2. **Bandwidth control**: no rate limiting
3. **QoS**: no quality-of-service guarantees
4. **IPv6**: IPv4 only
5. **Retransmission**: simple retry, no congestion control

## Future Improvements

1. **NAT traversal**: STUN/TURN
2. **QUIC**: replace custom UDP protocol
3. **Multiplexing**: multiple streams per connection
4. **Priority queue**: prioritize important messages
5. **Adaptive bandwidth**: adjust rate to network quality
6. **Relay nodes**: relay through third-party peers
