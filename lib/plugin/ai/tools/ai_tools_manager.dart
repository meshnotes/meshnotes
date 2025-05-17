import 'dart:convert';

import 'package:mesh_note/plugin/plugin_api.dart';
import 'package:my_log/my_log.dart';
import 'function_call.dart';

class AiToolsManager {
  PluginProxy pluginProxy;
  
  AiToolsManager({required this.pluginProxy});

  AiTools? buildTools() {
    final functions = _getAiFunctions();
    if(functions.isEmpty) {
      return null;
    }
    
    Map<String, AiFunctionCall> functionsMap = {};
    for(var function in functions) {
      functionsMap[function.name] = function;
    }
    return AiTools(functions: functionsMap);
  }

  List<AiFunctionCall> _getAiFunctions() {
    final createDocument = CreateNoteToolBuilder(pluginProxy: pluginProxy).build();
    final getAllDocumentList = GetAllDocumentListToolBuilder(pluginProxy: pluginProxy).build();
    final getDocumentContent = GetDocumentContentToolBuilder(pluginProxy: pluginProxy).build();
    final appendToDocument = AppendToDocumentToolBuilder(pluginProxy: pluginProxy).build();
    final openDocument = OpenDocumentToolBuilder(pluginProxy: pluginProxy).build();
    return [
      createDocument,
      getAllDocumentList,
      getDocumentContent,
      appendToDocument,
      openDocument,
    ];
  }
}

class CreateNoteToolBuilder {
  PluginProxy pluginProxy;
  CreateNoteToolBuilder({required this.pluginProxy});

  AiFunctionCall build() {
    final titleParameter = AiFunctionCallParameter(name: 'title', type: 'string', description: 'The title of the note', required: true);
    final contentParameter = AiFunctionCallParameter(name: 'content', type: 'string', description: 'The content of the note', required: true);
    return AiFunctionCall(
      name: 'create_note',
      description: 'Create a new note',
      parameters: {
        titleParameter.name: titleParameter,
        contentParameter.name: contentParameter,
      },
      onInvoke: _invoke,
    );
  }

  AiFunctionCallResult _invoke(Map<String, dynamic> parameters) {
    final title = parameters['title'];
    final content = parameters['content'];
    MyLogger.debug('Create note: $title $content');
    pluginProxy.createNote(title, content);
    return AiFunctionCallResult(result: 'Note has been created successfully.', shouldInformUser: true);
  }
}

class GetAllDocumentListToolBuilder {
  PluginProxy pluginProxy;
  GetAllDocumentListToolBuilder({required this.pluginProxy});

  AiFunctionCall build() {
    return AiFunctionCall(
      name: 'get_all_document_list',
      description: 'Get document list, return a list of document(including title, id, and some metadata)',
      parameters: {},
      onInvoke: _invoke,
    );
  }

  AiFunctionCallResult _invoke(Map<String, dynamic> parameters) {
    final documentList = pluginProxy.getAllDocumentList();
    var result = jsonEncode(documentList);
    return AiFunctionCallResult(result: result);
  }
}

class GetDocumentContentToolBuilder {
  PluginProxy pluginProxy;
  GetDocumentContentToolBuilder({required this.pluginProxy});

  AiFunctionCall build() {
    return AiFunctionCall(
      name: 'get_document_content',
      description: 'Get document\'s content by document id, which can be retrieved from get_all_document_list',
      parameters: {
        'document_id': AiFunctionCallParameter(name: 'document_id', type: 'string', description: 'The document id', required: true),
      },
      onInvoke: _invoke,
    );
  }

  AiFunctionCallResult _invoke(Map<String, dynamic> parameters) {
    final documentId = parameters['document_id'];
    final content = pluginProxy.getDocumentContent(documentId);
    return AiFunctionCallResult(result: content, shouldInformUser: true);
  }
}

class AppendToDocumentToolBuilder {
  PluginProxy pluginProxy;
  AppendToDocumentToolBuilder({required this.pluginProxy});

  AiFunctionCall build() {
    return AiFunctionCall(
      name: 'append_to_document',
      description: 'Append content to the end of document',
      parameters: {
        'document_id': AiFunctionCallParameter(name: 'document_id', type: 'string', description: 'The document id', required: true),
        'content': AiFunctionCallParameter(name: 'content', type: 'string', description: 'The content to append', required: true),
      },
      onInvoke: _invoke,
    );
  }

  AiFunctionCallResult _invoke(Map<String, dynamic> parameters) {
    final documentId = parameters['document_id'];
    final content = parameters['content'];
    pluginProxy.appendToDocument(documentId, content);
    return AiFunctionCallResult(result: 'Document content has been appended successfully.', shouldInformUser: true);
  }
}

class OpenDocumentToolBuilder {
  PluginProxy pluginProxy;
  OpenDocumentToolBuilder({required this.pluginProxy});

  AiFunctionCall build() {
    return AiFunctionCall(
      name: 'open_document',
      description: 'Open a document to make sure this document is displayed in the editor',
      parameters: {
        'document_id': AiFunctionCallParameter(name: 'document_id', type: 'string', description: 'The document id', required: true),
      },
      onInvoke: _invoke,
    );
  }

  AiFunctionCallResult _invoke(Map<String, dynamic> parameters) {
    final documentId = parameters['document_id'];
    final success = pluginProxy.openDocument(documentId);
    if(success) {
      return AiFunctionCallResult(isSuccess: true, result: 'Document has been opened successfully.', shouldInformUser: true);
    } else {
      return AiFunctionCallResult(isSuccess: false, result: 'Failed to open document.', shouldInformUser: true);
    }
  }
}
