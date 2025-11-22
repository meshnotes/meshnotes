# Mesh Notes - P2P Sync and Version Control

## Overview

Mesh Notes uses a Version Chain-based P2P sync mechanism that supports offline edits and automatic conflict resolution. Highlights:

- **Version DAG**: versions form a directed acyclic graph
- **Three-way merge**: resolve conflicts using a common ancestor
- **Tree operations**: add/delete/move/modify for the document tree
- **Eventual consistency**: all peers converge
- **Encrypted transport**: end-to-end encryption and signatures

## Version Chain Protocol

### Core concepts

**Version**:
- Each save creates a new version
- Contains version hash, parent hashes, timestamp, and document tree snapshot
- Versions form a DAG

**Object**:
- Actual document content
- Content-addressed (hash as ID)
- Deduplicated storage

**Document tree**:
- Hierarchical structure of all docs
- Each doc has ID, hash, updated time, parent ID

### Version structure

**Location**: [lib/mindeditor/document/collaborate/version_merge_manager.dart](../lib/mindeditor/document/collaborate/version_merge_manager.dart)

```dart
class VersionContent {
  List<VersionContentItem> table;   // Document tree snapshot
  int timestamp;                    // Version timestamp
  List<String> parentsHash;         // Parent hashes

  VersionContent({
    required this.table,
    required this.timestamp,
    required this.parentsHash,
  });

  // Calculate version hash
  String calculateHash() {
    final data = jsonEncode({
      'table': table.map((e) => e.toJson()).toList(),
      'timestamp': timestamp,
      'parents': parentsHash,
    });
    return HashUtil.hashText(data);
  }
}

class VersionContentItem {
  String docId;         // Doc ID
  String docHash;       // Doc content hash
  int updatedAt;        // Updated timestamp
  String? parentDocId;  // Parent doc ID
  int orderId;          // Order within parent

  VersionContentItem({
    required this.docId,
    required this.docHash,
    required this.updatedAt,
    this.parentDocId,
    required this.orderId,
  });
}
```

### Version DAG example

```
        V1 (initial)
       /  \
      /    \
    V2a    V2b  (two devices editing)
     |      |
    V3a    V3b
      \    /
       \  /
        V4  (merged)
```

**Notes**:
- A version can have multiple parents (merge)
- A version can have multiple children (fork)
- Sorted by timestamp
- Integrity verified by hashes

## Sync Flow

### 1. Version generation

**Location**: [lib/mindeditor/document/document_manager.dart](../lib/mindeditor/document/document_manager.dart:1380-1410)

```dart
class DocumentManager {
  Timer? _autoSaveTimer;
  bool _hasModified = false;

  void setModified() {
    _hasModified = true;
  }

  void startAutoSave() {
    // Check every 30s
    _autoSaveTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_hasModified) {
        genNewVersionTree();
      }
    });
  }

  void genNewVersionTree({String? parent}) {
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. Build version content
    final versionContent = _genVersionAndClearModified(now, [parent ?? _currentVersionHash]);

    // 2. Hash
    final versionHash = versionContent.calculateHash();

    // 3. Persist
    _storeVersionFromLocalAndUpdateCurrentVersion(versionContent, versionHash, now);

    // 4. Broadcast
    controller.network.sendVersionHash(versionHash);

    _hasModified = false;
  }

  VersionContent _genVersionAndClearModified(int timestamp, List<String> parents) {
    final items = <VersionContentItem>[];

    for (var node in _docTitles) {
      items.add(VersionContentItem(
        docId: node.docId,
        docHash: node.hash,
        updatedAt: node.timestamp,
        parentDocId: node.parentDocId,
        orderId: node.orderId,
      ));
    }

    return VersionContent(
      table: items,
      timestamp: timestamp,
      parentsHash: parents,
    );
  }
}
```

### 2. Version broadcast

**Location**: [lib/net/net_isolate.dart](../lib/net/net_isolate.dart:200-220)

```dart
class VersionChainVillager {
  Timer? _broadcastTimer;

  void start() {
    // Broadcast current hash every 30s
    _broadcastTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      _broadcastVersionHash();
    });
  }

  void _broadcastVersionHash() {
    final currentHash = _getCurrentVersionHash();

    final message = SignedMessage(
      userPublicId: _publicKey,
      data: jsonEncode({
        'type': 'version-hash',
        'hash': currentHash,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }),
      signature: _signing.sign(HashUtil.hashText(currentHash)),
    );

    _village.publish('version-hash', message.encode());
  }
}
```

### 3. Version request

```dart
void onVersionHashReceived(String remoteHash, String fromNodeId) {
  // 1. Already have it?
  if (_db.hasVersion(remoteHash)) {
    MyLogger.debug('Version $remoteHash already exists');
    return;
  }

  // 2. Need merge?
  final currentHash = _getCurrentVersionHash();
  if (remoteHash != currentHash) {
    MyLogger.info('Version differs, requesting full tree');

    // 3. Request full version tree
    _village.query([
      'version-tree:$remoteHash',
    ], targetNode: fromNodeId);
  }
}
```

### 4. Version transfer

```dart
void onVersionTreeQuery(String hash, String fromNodeId) {
  // 1. Load version
  final version = _db.getVersion(hash);
  if (version == null) {
    MyLogger.warn('Version $hash not found');
    return;
  }

  // 2. Find missing objects
  final missingObjects = <String>[];
  for (var item in version.table) {
    if (!_db.hasObject(item.docHash)) {
      missingObjects.add(item.docHash);
    }
  }

  // 3. Encrypt and sign version tree
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final versionData = jsonEncode(version.toJson());
  final encryptedVersion = _encrypt.encrypt(timestamp, versionData);

  final resource = SignedResource(
    id: 'version-tree:$hash',
    encryptedContent: encryptedVersion,
  );

  // 4. Sign resource list
  final signature = _signing.sign(
    HashUtil.hashText(jsonEncode([resource.toJson()])),
  );

  final signedResources = SignedResources(
    userPublicId: _publicKey,
    resources: [resource],
    signature: signature,
  );

  // 5. Send
  _village.provide(signedResources.encode(), targetNode: fromNodeId);

  // 6. Send missing objects
  _sendObjects(missingObjects, fromNodeId);
}

void _sendObjects(List<String> hashes, String targetNode) {
  const batchSize = 10;

  for (var i = 0; i < hashes.length; i += batchSize) {
    final batch = hashes.skip(i).take(batchSize).toList();
    final resources = <SignedResource>[];

    for (var hash in batch) {
      final content = _db.getObject(hash);
      if (content != null) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final encrypted = _encrypt.encrypt(timestamp, content);

        resources.add(SignedResource(
          id: hash,
          encryptedContent: encrypted,
        ));
      }
    }

    if (resources.isNotEmpty) {
      final signature = _signing.sign(
        HashUtil.hashText(jsonEncode(resources.map((e) => e.toJson()).toList())),
      );

      _village.provide(
        SignedResources(
          userPublicId: _publicKey,
          resources: resources,
          signature: signature,
        ).encode(),
        targetNode: targetNode,
      );
    }
  }
}
```

### 5. Version receive

```dart
void onVersionTreeReceived(SignedResources signedRes) {
  // 1. Verify signature
  final hash = HashUtil.hashText(
    jsonEncode(signedRes.resources.map((e) => e.toJson()).toList()),
  );
  final verifying = VerifyingWrapper(signedRes.userPublicId);
  if (!verifying.verify(hash, signedRes.signature)) {
    MyLogger.warn('Invalid signature for version tree');
    return;
  }

  // 2. Decrypt version tree
  for (var resource in signedRes.resources) {
    if (!resource.id.startsWith('version-tree:')) continue;

    final timestamp = _extractTimestamp(resource.encryptedContent);
    final versionData = _encrypt.decrypt(timestamp, resource.encryptedContent);
    final version = VersionContent.fromJson(jsonDecode(versionData));

    // 3. Store version
    final versionHash = resource.id.substring('version-tree:'.length);
    _db.saveVersion(versionHash, version);

    // 4. Check missing objects
    final missingObjects = <String>[];
    for (var item in version.table) {
      if (!_db.hasObject(item.docHash)) {
        missingObjects.add(item.docHash);
      }
    }

    // 5. Request missing objects
    if (missingObjects.isNotEmpty) {
      _village.query(missingObjects);
    } else {
      // 6. All ready → enqueue merge
      _addMergeTask(versionHash);
    }
  }
}

void onObjectsReceived(SignedResources signedRes) {
  // 1. Verify signature
  final hash = HashUtil.hashText(
    jsonEncode(signedRes.resources.map((e) => e.toJson()).toList()),
  );
  final verifying = VerifyingWrapper(signedRes.userPublicId);
  if (!verifying.verify(hash, signedRes.signature)) {
    MyLogger.warn('Invalid signature for objects');
    return;
  }

  // 2. Decrypt and store objects
  for (var resource in signedRes.resources) {
    final timestamp = _extractTimestamp(resource.encryptedContent);
    final content = _encrypt.decrypt(timestamp, resource.encryptedContent);

    _db.saveObject(resource.id, content);
  }

  // 3. Check pending merges
  _checkPendingMerges();
}
```

### 6. Merge scheduling

```dart
class MergeTaskQueue {
  final List<MergeTask> _queue = [];
  bool _isMerging = false;

  void addTask(MergeTask task) {
    _queue.add(task);
    _tryStartMerge();
  }

  void _tryStartMerge() {
    if (_isMerging || _queue.isEmpty) return;

    _isMerging = true;
    final task = _queue.removeAt(0);

    Future.microtask(() async {
      try {
        await _executeMerge(task);
      } catch (e) {
        MyLogger.error('Merge failed: $e');
      } finally {
        _isMerging = false;
        _tryStartMerge();  // process next task
      }
    });
  }

  Future<void> _executeMerge(MergeTask task) async {
    final merger = VersionMergeManager();
    await merger.merge(task.remoteVersionHash);
  }
}
```

## Conflict Resolution

### Three-way merge

**Location**: [lib/mindeditor/document/collaborate/version_merge_manager.dart](../lib/mindeditor/document/collaborate/version_merge_manager.dart:50-150)

```dart
class VersionMergeManager {
  Future<void> merge(String remoteVersionHash) async {
    final currentVersionHash = _getCurrentVersionHash();

    // 1. Find common ancestor
    final ancestor = _findCommonAncestor(currentVersionHash, remoteVersionHash);
    if (ancestor == null) {
      MyLogger.error('No common ancestor found');
      return;
    }

    MyLogger.info('Common ancestor: ${ancestor}');

    // 2. Load versions
    final ancestorVersion = _db.getVersion(ancestor)!;
    final currentVersion = _db.getVersion(currentVersionHash)!;
    final remoteVersion = _db.getVersion(remoteVersionHash)!;

    // 3. Generate operation lists
    final currentOps = _generateOperations(ancestorVersion, currentVersion);
    final remoteOps = _generateOperations(ancestorVersion, remoteVersion);

    // 4. Detect conflicts
    final conflicts = _detectConflicts(currentOps, remoteOps);

    // 5. Resolve conflicts
    final resolvedOps = _resolveConflicts(currentOps, remoteOps, conflicts);

    // 6. Apply operations
    _applyOperations(resolvedOps);

    // 7. Generate merged version
    final mergedVersion = _genMergedVersion(
      parents: [currentVersionHash, remoteVersionHash],
    );

    // 8. Save and update
    _db.saveVersion(mergedVersion.calculateHash(), mergedVersion);
    _setCurrentVersion(mergedVersion.calculateHash());

    // 9. Refresh UI
    CallbackRegistry.triggerDocumentChangedEvent();
  }

  String? _findCommonAncestor(String hash1, String hash2) {
    // BFS search
    final visited1 = <String>{};
    final visited2 = <String>{};
    final queue1 = Queue<String>()..add(hash1);
    final queue2 = Queue<String>()..add(hash2);

    while (queue1.isNotEmpty || queue2.isNotEmpty) {
      if (queue1.isNotEmpty) {
        final current = queue1.removeFirst();
        if (visited2.contains(current)) {
          return current;  // found
        }
        visited1.add(current);

        final version = _db.getVersion(current);
        if (version != null) {
          queue1.addAll(version.parentsHash);
        }
      }

      if (queue2.isNotEmpty) {
        final current = queue2.removeFirst();
        if (visited1.contains(current)) {
          return current;  // found
        }
        visited2.add(current);

        final version = _db.getVersion(current);
        if (version != null) {
          queue2.addAll(version.parentsHash);
        }
      }
    }

    return null;
  }
}
```

### Operation generation

**Location**: [lib/mindeditor/document/collaborate/diff_manager.dart](../lib/mindeditor/document/collaborate/diff_manager.dart)

```dart
enum TreeOperationType {
  add,      // Add doc
  del,      // Delete doc
  move,     // Move doc
  modify,   // Modify content
}

class TreeOperation {
  TreeOperationType type;
  String id;              // Target doc ID
  String? parentId;       // Parent (for add/move)
  int? orderId;           // Order (for add/move)
  String? newData;        // New content hash (for add/modify)
  int timestamp;          // Timestamp

  TreeOperation({
    required this.type,
    required this.id,
    this.parentId,
    this.orderId,
    this.newData,
    required this.timestamp,
  });
}

class DiffManager {
  List<TreeOperation> generateOperations(
    VersionContent from,
    VersionContent to,
  ) {
    final operations = <TreeOperation>[];

    // 1. Build maps
    final fromMap = {for (var item in from.table) item.docId: item};
    final toMap = {for (var item in to.table) item.docId: item};

    // 2. Find deletions
    for (var fromItem in from.table) {
      if (!toMap.containsKey(fromItem.docId)) {
        operations.add(TreeOperation(
          type: TreeOperationType.del,
          id: fromItem.docId,
          timestamp: to.timestamp,
        ));
      }
    }

    // 3. Find additions and modifications
    for (var toItem in to.table) {
      if (!fromMap.containsKey(toItem.docId)) {
        // Add
        operations.add(TreeOperation(
          type: TreeOperationType.add,
          id: toItem.docId,
          parentId: toItem.parentDocId,
          orderId: toItem.orderId,
          newData: toItem.docHash,
          timestamp: to.timestamp,
        ));
      } else {
        final fromItem = fromMap[toItem.docId]!;

        // Content change
        if (fromItem.docHash != toItem.docHash) {
          operations.add(TreeOperation(
            type: TreeOperationType.modify,
            id: toItem.docId,
            newData: toItem.docHash,
            timestamp: to.timestamp,
          ));
        }

        // Position change
        if (fromItem.parentDocId != toItem.parentDocId ||
            fromItem.orderId != toItem.orderId) {
          operations.add(TreeOperation(
            type: TreeOperationType.move,
            id: toItem.docId,
            parentId: toItem.parentDocId,
            orderId: toItem.orderId,
            timestamp: to.timestamp,
          ));
        }
      }
    }

    return operations;
  }
}
```

### Conflict detection

```dart
class ConflictDetector {
  List<Conflict> detectConflicts(
    List<TreeOperation> ops1,
    List<TreeOperation> ops2,
  ) {
    final conflicts = <Conflict>[];

    // Group by doc ID
    final opsMap1 = _groupByDocId(ops1);
    final opsMap2 = _groupByDocId(ops2);

    // Find conflicts on the same doc
    for (var docId in opsMap1.keys) {
      if (opsMap2.containsKey(docId)) {
        final docOps1 = opsMap1[docId]!;
        final docOps2 = opsMap2[docId]!;

        final conflict = _checkConflict(docId, docOps1, docOps2);
        if (conflict != null) {
          conflicts.add(conflict);
        }
      }
    }

    return conflicts;
  }

  Conflict? _checkConflict(
    String docId,
    List<TreeOperation> ops1,
    List<TreeOperation> ops2,
  ) {
    // Conflict types:
    // 1. add + add: same ID added twice
    // 2. modify + modify: content conflict
    // 3. modify + del: edit vs delete
    // 4. move + del: move vs delete
    // 5. move + move: moved to different places

    final types1 = ops1.map((op) => op.type).toSet();
    final types2 = ops2.map((op) => op.type).toSet();

    if (types1.contains(TreeOperationType.modify) &&
        types2.contains(TreeOperationType.modify)) {
      return Conflict(
        type: ConflictType.contentConflict,
        docId: docId,
        ops1: ops1,
        ops2: ops2,
      );
    }

    if ((types1.contains(TreeOperationType.modify) && types2.contains(TreeOperationType.del)) ||
        (types1.contains(TreeOperationType.del) && types2.contains(TreeOperationType.modify))) {
      return Conflict(
        type: ConflictType.modifyDeleteConflict,
        docId: docId,
        ops1: ops1,
        ops2: ops2,
      );
    }

    if (types1.contains(TreeOperationType.move) &&
        types2.contains(TreeOperationType.move)) {
      final move1 = ops1.firstWhere((op) => op.type == TreeOperationType.move);
      final move2 = ops2.firstWhere((op) => op.type == TreeOperationType.move);

      if (move1.parentId != move2.parentId || move1.orderId != move2.orderId) {
        return Conflict(
          type: ConflictType.moveConflict,
          docId: docId,
          ops1: ops1,
          ops2: ops2,
        );
      }
    }

    return null;
  }

  Map<String, List<TreeOperation>> _groupByDocId(List<TreeOperation> ops) {
    final map = <String, List<TreeOperation>>{};
    for (var op in ops) {
      map.putIfAbsent(op.id, () => []).add(op);
    }
    return map;
  }
}
```

### Conflict resolution strategy

```dart
class ConflictResolver {
  List<TreeOperation> resolveConflicts(
    List<TreeOperation> ops1,
    List<TreeOperation> ops2,
    List<Conflict> conflicts,
  ) {
    final resolved = <TreeOperation>[];

    // 1. Add all non-conflicting ops
    final conflictDocIds = conflicts.map((c) => c.docId).toSet();
    resolved.addAll(ops1.where((op) => !conflictDocIds.contains(op.id)));
    resolved.addAll(ops2.where((op) => !conflictDocIds.contains(op.id)));

    // 2. Resolve conflicts
    for (var conflict in conflicts) {
      switch (conflict.type) {
        case ConflictType.contentConflict:
          // Keep both versions, record conflict
          resolved.addAll(_resolveContentConflict(conflict));
          break;

        case ConflictType.modifyDeleteConflict:
          // Keep the latest
          resolved.add(_resolveByTimestamp(conflict));
          break;

        case ConflictType.moveConflict:
          // Keep the latest move
          resolved.add(_resolveByTimestamp(conflict));
          break;

        case ConflictType.addConflict:
          // Keep the latest add
          resolved.add(_resolveByTimestamp(conflict));
          break;
      }
    }

    return resolved;
  }

  List<TreeOperation> _resolveContentConflict(Conflict conflict) {
    // Produce conflict entry
    final op1 = conflict.ops1.firstWhere((op) => op.type == TreeOperationType.modify);
    final op2 = conflict.ops2.firstWhere((op) => op.type == TreeOperationType.modify);

    // Keep the latest edit
    final latest = op1.timestamp > op2.timestamp ? op1 : op2;

    // Record conflict in DB
    _recordContentConflict(
      docId: conflict.docId,
      hash1: op1.newData!,
      hash2: op2.newData!,
      timestamp1: op1.timestamp,
      timestamp2: op2.timestamp,
    );

    return [latest];
  }

  TreeOperation _resolveByTimestamp(Conflict conflict) {
    final allOps = [...conflict.ops1, ...conflict.ops2];
    allOps.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return allOps.first;
  }

  void _recordContentConflict({
    required String docId,
    required String hash1,
    required String hash2,
    required int timestamp1,
    required int timestamp2,
  }) {
    _db.saveConflict(ContentConflict(
      targetId: docId,
      originalHash: _getOriginalHash(docId),
      conflictHash1: hash1,
      conflictHash2: hash2,
      timestamp1: timestamp1,
      timestamp2: timestamp2,
    ));

    // Notify user
    CallbackRegistry.showToast('Document $docId has a conflict, please resolve it manually');
  }
}
```

### Applying operations

```dart
class OperationApplier {
  void applyOperations(List<TreeOperation> operations) {
    // Sort by type/timestamp (deletions last)
    operations.sort((a, b) {
      if (a.type == TreeOperationType.del && b.type != TreeOperationType.del) {
        return 1;
      }
      if (b.type == TreeOperationType.del && a.type != TreeOperationType.del) {
        return -1;
      }
      return a.timestamp.compareTo(b.timestamp);
    });

    for (var op in operations) {
      switch (op.type) {
        case TreeOperationType.add:
          _applyAdd(op);
          break;
        case TreeOperationType.del:
          _applyDelete(op);
          break;
        case TreeOperationType.move:
          _applyMove(op);
          break;
        case TreeOperationType.modify:
          _applyModify(op);
          break;
      }
    }
  }

  void _applyAdd(TreeOperation op) {
    // Create doc node
    final node = DocTitleMeta(
      docId: op.id,
      title: _getDocumentTitle(op.newData!),
      hash: op.newData!,
      isPrivate: 0,
      timestamp: op.timestamp,
      orderId: op.orderId ?? 0,
      parentDocId: op.parentId,
    );

    // Insert into tree
    _insertDocumentNode(node);

    // Persist
    _db.insertDocument(node);
  }

  void _applyDelete(TreeOperation op) {
    _removeDocumentNode(op.id);
    _db.deleteDocument(op.id);
  }

  void _applyMove(TreeOperation op) {
    final node = _findDocumentNode(op.id);
    if (node != null) {
      node.parentDocId = op.parentId;
      node.orderId = op.orderId ?? 0;

      _removeDocumentNode(op.id);
      _insertDocumentNode(node);

      _db.updateDocParent(op.id, op.parentId);
      _db.updateDocOrderId(op.id, op.orderId ?? 0);
    }
  }

  void _applyModify(TreeOperation op) {
    final node = _findDocumentNode(op.id);
    if (node != null) {
      node.hash = op.newData!;
      node.timestamp = op.timestamp;

      _db.updateDocHash(op.id, op.newData!);
      _db.updateDocTimestamp(op.id, op.timestamp);
    }
  }
}
```

## Database Design

### Tables

**Location**: [lib/mindeditor/document/dal/db_helper.dart](../lib/mindeditor/document/dal/db_helper.dart:50-150)

#### 1. documents (metadata)

```sql
CREATE TABLE documents (
  doc_id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  hash TEXT NOT NULL,
  is_private INTEGER DEFAULT 0,
  timestamp INTEGER NOT NULL,
  parent_doc_id TEXT,
  order_id INTEGER DEFAULT 0,
  FOREIGN KEY (parent_doc_id) REFERENCES documents(doc_id)
);

CREATE INDEX idx_documents_parent ON documents(parent_doc_id);
CREATE INDEX idx_documents_hash ON documents(hash);
```

#### 2. blocks (block content)

```sql
CREATE TABLE blocks (
  block_id TEXT PRIMARY KEY,
  doc_id TEXT NOT NULL,
  content TEXT NOT NULL,
  block_type INTEGER NOT NULL,
  listing INTEGER DEFAULT 0,
  level INTEGER DEFAULT 0,
  order_id INTEGER NOT NULL,
  FOREIGN KEY (doc_id) REFERENCES documents(doc_id) ON DELETE CASCADE
);

CREATE INDEX idx_blocks_doc ON blocks(doc_id);
```

#### 3. versions (version DAG)

```sql
CREATE TABLE versions (
  version_hash TEXT PRIMARY KEY,
  content TEXT NOT NULL,  -- JSON VersionContent
  timestamp INTEGER NOT NULL,
  parents TEXT NOT NULL   -- JSON parent hashes
);

CREATE INDEX idx_versions_timestamp ON versions(timestamp);
```

#### 4. objects (content-addressed storage)

```sql
CREATE TABLE objects (
  object_hash TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  size INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
```

#### 5. conflicts (conflict records)

```sql
CREATE TABLE conflicts (
  conflict_id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_id TEXT NOT NULL,
  original_hash TEXT NOT NULL,
  conflict_hash1 TEXT NOT NULL,
  conflict_hash2 TEXT NOT NULL,
  timestamp1 INTEGER NOT NULL,
  timestamp2 INTEGER NOT NULL,
  resolved INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE INDEX idx_conflicts_target ON conflicts(target_id);
CREATE INDEX idx_conflicts_resolved ON conflicts(resolved);
```

## Performance

### 1. Incremental sync

Send only changed objects:

```dart
List<String> findMissingObjects(VersionContent version) {
  final missing = <String>[];

  for (var item in version.table) {
    if (!_db.hasObject(item.docHash)) {
      missing.add(item.docHash);
    }
  }

  return missing;
}
```

### 2. Batch transfer

```dart
void sendObjects(List<String> hashes, String targetNode) {
  const batchSize = 10;

  for (var i = 0; i < hashes.length; i += batchSize) {
    final batch = hashes.skip(i).take(batchSize).toList();
    _sendObjectBatch(batch, targetNode);
  }
}
```

### 3. Deduplication

Avoid resending identical content:

```dart
String saveDocument(String docId, String content) {
  final hash = HashUtil.hashText(content);

  if (_db.hasObject(hash)) {
    MyLogger.debug('Object $hash already exists, skip saving');
  } else {
    _db.saveObject(hash, content);
  }

  _db.updateDocHash(docId, hash);

  return hash;
}
```

### 4. Deferred merge

Merge only when idle to avoid blocking UI:

```dart
void addMergeTask(String versionHash) {
  _mergeQueue.add(versionHash);

  Future.delayed(Duration(seconds: 1), () {
    if (!_isMerging) {
      _processMergeQueue();
    }
  });
}
```

## Known Limitations

1. **Large documents**: slow transfer for very large docs
2. **Conflict resolution**: content conflicts require manual resolution
3. **Network drops**: requires manual reconnect
4. **Version history**: no history viewer

## Future Work

1. **Incremental sync**: sync changed blocks instead of whole docs
2. **Smarter conflict resolution**: auto-merge text conflicts
3. **Version compaction**: periodically compress old versions
4. **Garbage collection**: delete unreferenced objects
5. **Resumable transfer**: breakpoint resume for big files
6. **Version browser**: visualize history and DAG
7. **Selective sync**: sync only chosen documents
