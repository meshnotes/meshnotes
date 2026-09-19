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

**Location**: [packages/libp2p/lib/network/network_layer.dart](../packages/libp2p/lib/network/network_layer.dart)

#### Connection management

For an incoming `connect` at the same IP/UDP port, compare its `sourceConnectionId` with the existing peer's **destination** ID:
- Same ID: ignore a duplicate on an established session; resend `connectAck` on an establishing session.
- Different ID: remove the old session, clear its handshake retries and notify its disconnect callback before creating a fresh peer. Do not send `bye` during replacement.
- An invalid/shutdown record must not block a new handshake, even with the same ID. A simultaneous outgoing handshake whose remote ID is still zero is reused and learns the incoming ID.

`connectAck`/`connected` must match the endpoint and session IDs, so delayed old handshake packets cannot establish or retarget the replacement.
Connection-pool removal checks peer identity; overlay disconnect callbacks also match the peer instance, not merely its address.
This avoids waiting for heartbeat expiry after a client restarts on the same UDP endpoint. Connection IDs are not authentication or replay protection.

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
  Future<void> startAdvertising() async {
    // Broadcast our service
    final service = BonsoirService(
      name: _deviceId,
      type: '_meshnotes._udp',
      port: _port,
    );
    final broadcast = BonsoirBroadcast(service: service);
    await broadcast.initialize();
    await broadcast.start();
  }

  Future<void> startDiscovery() async {
    // Listen for other services
    final discovery = BonsoirDiscovery(type: '_meshnotes._udp');
    await discovery.initialize();
    discovery.eventStream!.listen((event) {
      switch(event) {
        case BonsoirDiscoveryServiceFoundEvent():
          event.service.resolve(discovery.serviceResolver);
        case BonsoirDiscoveryServiceResolvedEvent():
          _onServiceFound(event.service);
        default:
          break;
      }
    });
    await discovery.start();
  }
}
```

#### 2. Manual peers (Sponsor)

The `Allow sending data to public server` (`allow_sending_to_public_server`) setting controls whether peer-to-peer business sync data is allowed to be transmitted to nodes with different user public keys. If disabled, the client filters outgoing messages to only send to peers having matching user public keys. Standalone relay servers pass the overlay option as enabled so the server side can store/query data for any user public key, while app-side receive/merge handling still keeps the default current-user-only data boundary.

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

Configured sponsor nodes are upper nodes and reconnect after either an initial failure or a lost connection. Nodes created from inbound connections are not upper nodes,
so disconnecting them removes them instead of making the accepting peer reconnect back. Standalone relay servers likewise remove an active-connection entry whenever
its node leaves `keepInTouch`, regardless of the specific failure status.

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

All messages are signed. Uncipher messages are unencrypted control envelopes, while Cipher messages contain encrypted resource payloads:

- **UncipherMessage**: Used for unencrypted control messages (e.g. `publish`, `query`, `offer`, `apply`).
- **CipherMessage**: Used for encrypted resources (e.g. `provide` containing encrypted versions or objects).

```dart
class UncipherMessage {
  String userPublicId;      // Sender public key ('user' in JSON)
  String data;              // Payload (JSON string)
  String signature;         // signature = sign(hash(data)) ('sign' in JSON)
}
```

**Verification**:
```dart
bool verify(UncipherMessage msg) {
  final hash = HashUtil.hashText(msg.data);
  return VerifyingWrapper(msg.userPublicId).verify(hash, msg.signature);
}
```

#### Resource format (CipherMessage)

```dart
class CipherMessages {
  String userPublicId;
  List<CipherMessage> resources;
  String signature;         // signature = sign(hash(resources))
}

class CipherMessage {
  String key;               // Resource key (hash)
  String subKey;            // Sub-key
  int timestamp;            // Resource timestamp
  String data;              // Encrypted content (using AES)
  String signature;         // signature = sign(hash(features))
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

**1. Version broadcast (publish)**:
`publish` is used for unencrypted broadcasting. It includes a `type` field (currently `versionChainBroadcastType`, because the announced latest hash is the entry point of the version chain).
```dart
const String versionChainBroadcastType = 'version_chain';

// Broadcast version hash and its app-side version timestamp every 30s
Timer.periodic(Duration(seconds: 30), (timer) {
  final currentVersionHash = _getCurrentVersionHash();
  final currentVersionTimestamp = _getCurrentVersionTimestamp();
  _village.publish(jsonEncode({
    'type': versionChainBroadcastType,
    'messages': {
      'latest_version': currentVersionHash,
      'latest_version_timestamp': currentVersionTimestamp.toString(),
    }
  }));
});
```

Standalone relay servers use `latest_version_timestamp` only as an announced version-tree timestamp for comparison. If a repeated publish has the same `latest_version`, and the stored encrypted `version_tree` resource has the same resource timestamp, the server skips initiating offer/apply to avoid repeated sync loops.

**2. Offer**:
`offer` is a generic, signed, unencrypted message. The outer `UncipherMessage.data` contains a generic `Offer` JSON string. This implementation currently uses `offerTypeStorage`; storage-specific fields such as `limit` and `extra` are stored directly in `Offer.data` as a JSON map.

When a standalone relay server receives a `publish` message, it checks if it needs to sync the client's latest versions. If yes, it sends an `offer` message to the client (not encrypted):
```dart
const String offerTypeStorage = 'storage';
const String applyTypeVersion = 'version';

class Offer {
  String type; // offerTypeStorage
  String target; // data owner's public key
  Map<String, dynamic> data; // {'limit': 100, 'extra': ''}
}
```

`Offer.target` always names the **data owner** (the user whose version chain this offer is about), not the peer that currently holds a copy.

- **App only**: MeshNotes stores only the current user's data, so the app additionally requires `target` to equal the local user's public key before answering (`lib/net/net_isolate.dart` `_handleOffer` and `lib/mindeditor/controller/controller.dart` `receiveOffer`). Offers for any other `target` are ignored.
- **Server-to-server**: a relay stores objects for many users. `target` is still the data owner, **not** the receiving server's own public key. The receiving server must not require `target == self`; it uses `target` to select which owner's data to apply.

**3. Apply**:
When the MeshNotes app receives an `offer` with `type == offerTypeStorage` and `target` equal to the local user's public key, it reads storage fields directly from `Offer.data`, calculates all version hashes in its local DAG, and replies with an `Apply` message (not encrypted) containing all versions:
```dart
class Apply {
  String type; // applyTypeVersion
  Map<String, dynamic> data; // {'versions': [...]} all version hashes in the local DAG for applyTypeVersion
}
```

**4. Storage Query**:
Upon receiving the `Apply` message, the server checks which version hashes are missing from its database, and requests them from the client using `query` (not encrypted):
```dart
class RequireVersions {
  List<String> requiredVersions;
}
```

**5. Storage Provide**:
The client receives the query and sends back the missing encrypted versions/objects using `provide` (`CipherMessages` containing `CipherMessage` items).

**6. Legacy Version request (fallback)**:

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
  final uncipherMessage = UncipherMessage(
    userPublicId: _publicKey,
    data: data,
    signature: signature,
  );

  // 5. Publish
  _village.publish('message', uncipherMessage.encode());
}
```

#### Receive message

```dart
void onMessageReceived(UncipherMessage msg) {
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
  final resource = CipherMessage(
    id: id,
    encryptedContent: encryptedContent,
  );

  // 3. Sign resource list
  final hash = HashUtil.hashText(jsonEncode([resource]));
  final signature = _signing.sign(hash);

  // 4. Send
  final cipherMessages = CipherMessages(
    userPublicId: _publicKey,
    resources: [resource],
    signature: signature,
  );

  _village.provide(cipherMessages.encode());
}
```

#### Receive resource

```dart
void onResourceReceived(CipherMessages res) {
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

## Standalone Relay Server Unified Storage

The standalone relay server acts as a persistent bootstrap and storage peer that does not require an active sponsor. It implements unified object storage:

1. **Provide Message (`provideAppType`)**:
   - Parses incoming `CipherMessages`.
   - Stores each resource inside the `objects` table under the joint primary key `(user_public_key, key)`.
   - If the resource key is `version_tree`, it upserts (overwrites) the old value.
   - For all other keys (representing immutable versions or blocks), it inserts with `OR IGNORE` (does not overwrite existing).
   - Retains the full outer `CipherMessages` JSON (envelope) for each resource so it can be returned verbatim without server re-signing.

2. **Query Message (`queryAppType`)**:
   - Parses incoming query wrapping a `RequireVersions` list inside a `UncipherMessage`.
   - Resolves all database records matching `userPublicId` and any of the requested keys.
   - Returns the original matching `CipherMessages` envelopes (as multiple messages if necessary) back to the querying peer.

3. **Publish Message (`publishAppType`)**:
   - Parses `UncipherMessage` wrapping a `BroadcastMessages`.
   - Records the `latest_version` in the `latest_versions` table. Its `updated_at` remains the server receive/update time, not the app-side version-tree timestamp.
   - Uses the published `latest_version_timestamp` only for comparison against the stored `version_tree` resource timestamp.
   - If a repeated publish has the same `latest_version`, and the stored encrypted `version_tree` resource timestamp equals the published `latest_version_timestamp`, it skips querying the tree again.
   - Otherwise, when the corresponding latest version object is not cached, it sends an `offerAppType` request with `Offer(type: offerTypeStorage, target: data owner / publishing user, data: {'limit': 100, 'extra': ''})`. `target` is the owner's public key even when the peer is another relay, not the receiving server's key.
   - After the client answers with `applyAppType`, the server sends an app-compatible `queryAppType` request for only the missing version hashes.
   - The query format is identical to MeshNotes app: `UncipherMessage.user` is the querying server's public key, `UncipherMessage.data` is `RequireVersions { versions }`, and `UncipherMessage.sign` verifies against that same server key.
   - Does not relay the publish payload to other peers yet, to avoid relay storms until forwarded `latest_version` tracking is implemented.
