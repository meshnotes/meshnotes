import 'dart:convert';

class UserNotes {
  List<UserNote> notes;

  UserNotes({required this.notes});

  Map<String, dynamic> toJson() {
    return {
      'notes': notes,
    };
  }

  String getNotesContent() {
    return jsonEncode(toJson());
  }
}

class UserNote {
  String noteId;
  String title;
  List<NoteContent> contents;

  UserNote({required this.noteId, required this.title, required this.contents});

  Map<String, dynamic> toJson() {
    return {
      'note_id': noteId,
      'title': title,
      'contents': contents,
    };
  }
}

class NoteContent {
  String blockId;
  String content;

  NoteContent({required this.blockId, required this.content});

  Map<String, dynamic> toJson() {
    return {
      'block_id': blockId,
      'content': content,
    };
  }
}