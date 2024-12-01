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
    return [
      createDocument,
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
    return AiFunctionCallResult(result: 'Note has been created successfully.');
  }
}