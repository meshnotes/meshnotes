import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:my_log/my_log.dart';
import '../mindeditor/document/doc_title_node.dart';

/// Only IDs and titles cross into the home-screen process; never document content.
List<Map<String, String>> buildRecentNotesSnapshot(List<DocTitleMeta> documents, List<String> recentIds) {
  // TODO: Return early when six recent notes are valid; only sort documents when more notes are needed.
  final byId = {
    for(final doc in documents) doc.docId: doc
  };
  final sorted = [...documents]..sort((a, b) {
    final time = b.timestamp.compareTo(a.timestamp);
    return time != 0 ? time : a.docId.compareTo(b.docId);
  });
  final ids = {
    ...recentIds,
    ...sorted.map((doc) => doc.docId)
  };
  return ids.where(byId.containsKey).take(6).map((id) {
    final title = byId[id]!.title.trim().replaceAll(RegExp(r'[\r\n]+'), ' ');
    return {
      'id': id,
      'title': title.isEmpty? 'Untitled note' : title
    };
  }).toList();
}

class WidgetNoteAction {
  final String? documentId;
  bool get isNew => documentId == null;
  const WidgetNoteAction._(this.documentId);

  static WidgetNoteAction? parse(String link) {
    final uri = Uri.tryParse(link);
    if(uri == null || uri.scheme != 'meshnotes' || uri.host != 'widget' || uri.hasQuery || uri.hasFragment) return null;
    final parts = uri.pathSegments;
    if(parts.length == 1 && parts.first == 'new') return const WidgetNoteAction._(null);
    if(parts.length == 2 && parts.first == 'open' && parts[1].isNotEmpty) return WidgetNoteAction._(parts[1]);
    return null;
  }
}

class RecentNotesWidgetBridge {
  static const _channel = MethodChannel('xyz.meshnotes/recent_notes');
  String? _lastSnapshot;

  Future<void> initialize(void Function(WidgetNoteAction) onAction) async {
    void receive(String? link) {
      final action = link == null ? null : WidgetNoteAction.parse(link);
      if(action != null) onAction(action);
    }
    _channel.setMethodCallHandler((call) async {
      if(call.method == 'openLink') receive(call.arguments as String?);
    });
    try {
      receive(await _channel.invokeMethod<String>('takePendingLink'));
    } on PlatformException catch(e) {
      MyLogger.warn('Widget link initialization failed: ${e.code}');
    }
  }

  Future<void> update(List<Map<String, String>> notes) async {
    final snapshot = jsonEncode(notes);
    if(snapshot == _lastSnapshot) return;
    try {
      await _channel.invokeMethod<void>('updateNotes', snapshot);
      _lastSnapshot = snapshot;
    } on PlatformException catch(e) {
      MyLogger.warn('Widget snapshot update failed: ${e.code}');
    }
  }

  void dispose() => _channel.setMethodCallHandler(null);
}
