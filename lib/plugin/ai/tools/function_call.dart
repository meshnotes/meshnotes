import 'dart:convert';

class AiTools {
  final Map<String, AiFunctionCall> functions;

  AiTools({required this.functions});

  List<Map<String, dynamic>> getDescription() {
    final List<Map<String, dynamic>> descriptions = [];
    for(var function in functions.values) {
      final functionDescription = {
        'name': function.name,
        'description': function.description,
        'type': 'function',
        'parameters': function.getParameters(),
      };
      descriptions.add(functionDescription);
    }
    return descriptions;
  }

  
  AiFunctionCallResult? invokeFunction(String name, String arguments) {
    final function = functions[name];
    return function?.onInvoke(jsonDecode(arguments));
  }
}

class AiFunctionCall {
  final String name;
  final String description;
  final Map<String, AiFunctionCallParameter> parameters;
  final AiFunctionCallResult Function(Map<String, dynamic>) onInvoke;

  AiFunctionCall({required this.name, required this.description, required this.parameters, required this.onInvoke});

  Map<String, dynamic> getParameters() {
    return {
      'type': 'object',
      'properties': _buildParameters(),
      'required': _buildRequiredParameters(),
    };
  }

  AiFunctionCallResult call(Map<String, dynamic> parameters) {
    return onInvoke(parameters);
  }

  Map<String, dynamic> _buildParameters() {
    final Map<String, dynamic> result = {};
    for(var parameter in parameters.values) {
      result[parameter.name] = parameter.getParameterDescription();
    }
    return result;
  }

  List<String> _buildRequiredParameters() {
    final List<String> requiredParameters = [];
    for(var parameter in parameters.values) {
      if(parameter.required) {
        requiredParameters.add(parameter.name);
      }
    }
    return requiredParameters;
  }
}

class AiFunctionCallParameter {
  final String name;
  final String type;
  final String description;
  final bool required;

  AiFunctionCallParameter({required this.name, required this.type, required this.description, required this.required});

  Map<String, dynamic> getParameterDescription() {
    return {
      'type': type,
      'description': description,
    };
  }
}

class AiFunctionCallResult {
  final String result;
  final bool isSuccess;
  final bool needRetry;
  final bool shouldInformUser;

  AiFunctionCallResult({
    required this.result,
    this.isSuccess = true,
    this.needRetry = false,
    this.shouldInformUser = true,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'result': result,
      'is_success': isSuccess,
    };
    if(needRetry) {
      json['need_retry'] = needRetry;
    }
    if(shouldInformUser) {
      json['should_inform_user'] = shouldInformUser;
    }
    return json;
  }
}
