String _hexMap = '0123456789abcdef';

String bytes2Hex(List<int> bin) {
  String result = '';
  for(final d in bin) {
    int c = d & 0xFF;
    final lower = _hexMap[c % 16];
    final higher = _hexMap[c ~/ 16];
    result += higher + lower;
  }
  return result;
}