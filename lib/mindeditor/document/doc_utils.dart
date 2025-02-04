import 'dart:convert';

import 'package:mesh_note/net/version_chain_api.dart';
import 'package:my_log/my_log.dart';

import 'dal/db_helper.dart';
import 'doc_content.dart';

class DocUtils {
  static String buildParents(List<String> parents) {
    String result = '';
    for(var p in parents) {
      if(result.isEmpty) {
        result = p;
      } else {
        result += ',' + p;
      }
    }
    return result;
  }

  /// Used in requestor
  static Map<String, RelatedObject> genDependingObjects(VersionContent versionContent, DbHelper _db, {bool findSyncingObject = false}) {
    Map<String, RelatedObject> result = {};
    for(var item in versionContent.table) {
      var docId = item.docId;
      var docHash = item.docHash;
      var docObject = _db.getObject(docHash)?? (findSyncingObject? _db.getSyncingObject(docHash): null);
      if(docObject == null) {
        MyLogger.info('_genRequiredObjects: document is missing! docId=$docId, docHash=$docHash');
        result[docHash] = RelatedObject(objHash: docHash, objContent: '', createdAt: 0); // Different from genRequiredObjects
        continue;
      }
      MyLogger.info('_genRequiredObjects: docId=$docId, docHash=$docHash, docStr=$docObject');
      result[docHash] = RelatedObject(objHash: docHash, objContent: docObject.data, createdAt: docObject.timestamp);

      //TODO should load history document by docHash
      var docContent = DocContent.fromJson(jsonDecode(docObject.data));
      for(var block in docContent.contents) {
        _recursiveGenDependingBlocks(block, result, _db, findSyncingObject);
      }
    }
    return result;
  }
  static void _recursiveGenDependingBlocks(DocContentItem block, Map<String, RelatedObject> map, DbHelper _db, bool findSyncingObject) {
    var blockHash = block.blockHash;
    if(!map.containsKey(blockHash)) {
      var blockObject = _db.getObject(blockHash)?? (findSyncingObject? _db.getSyncingObject(blockHash): null);
      if(blockObject == null) {
        map[blockHash] = RelatedObject(objHash: blockHash, objContent: '', createdAt: 0); // Different from _recursiveGenRequiredBlocks
        return;  
      }
      map[blockHash] = RelatedObject(objHash: blockHash, objContent: blockObject.data, createdAt: blockObject.timestamp);
    }
    for(var item in block.children) {
      _recursiveGenDependingBlocks(item, map, _db, findSyncingObject);
    }
  }
  /// Used in provider
  static Map<String, RelatedObject> genRequiredObjects(VersionContent versionContent, DbHelper _db, {bool findSyncingObject = false}) {
    Map<String, RelatedObject> result = {};
    for(var item in versionContent.table) {
      var docId = item.docId;
      var docHash = item.docHash;
      var docObject = _db.getObject(docHash)?? (findSyncingObject? _db.getSyncingObject(docHash): null);
      if(docObject == null) continue;
      MyLogger.info('_genRequiredObjects: docId=$docId, docHash=$docHash, docStr=$docObject');
      result[docHash] = RelatedObject(objHash: docHash, objContent: docObject.data, createdAt: docObject.timestamp);

      //TODO should load history document by docHash
      var docContent = DocContent.fromJson(jsonDecode(docObject.data));
      for(var block in docContent.contents) {
        _recursiveGenRequiredBlocks(block, result, _db, findSyncingObject);
      }
    }
    return result;
  }
  static void _recursiveGenRequiredBlocks(DocContentItem block, Map<String, RelatedObject> map, DbHelper _db, bool findSyncingObject) {
    var blockHash = block.blockHash;
    if(!map.containsKey(blockHash)) {
      var blockObject = _db.getObject(blockHash)?? (findSyncingObject? _db.getSyncingObject(blockHash): null);
      if(blockObject == null) return;
      map[blockHash] = RelatedObject(objHash: blockHash, objContent: blockObject.data, createdAt: blockObject.timestamp);
    }
    for(var item in block.children) {
      _recursiveGenRequiredBlocks(item, map, _db, findSyncingObject);
    }
  }
}