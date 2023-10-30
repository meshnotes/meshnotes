class NetworkEnvSimulator {
  bool Function(List<int>)? sendHook;

  static NetworkEnvSimulator dropAll = NetworkEnvSimulator()..sendHook = (_) => false;
  static NetworkEnvSimulator acceptAll = NetworkEnvSimulator()..sendHook = (_) => true;
}