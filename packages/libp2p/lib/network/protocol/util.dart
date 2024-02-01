void fillBytes8(List<int> list, int start, int value) {
  if(list.length - start < 1) return;
  int byte = value & 0xFF;
  list[start] = byte;
}

void fillBytes16(List<int> list, int start, int value) {
  if(list.length - start < 2) return;
  int byte0 = (value >> 8) & 0xFF;
  int byte1 = value & 0xFF;
  list[start] = byte0;
  list[start + 1] = byte1;
}

void fillBytes32(List<int> list, int start, int value) {
  if(list.length - start < 4) {
    return;
  }
  int byte0 = (value >> 24) & 0xFF;
  int byte1 = (value >> 16) & 0xFF;
  int byte2 = (value >> 8) & 0xFF;
  int byte3 = value & 0xFF;
  list[start] = byte0;
  list[start + 1] = byte1;
  list[start + 2] = byte2;
  list[start + 3] = byte3;
}

int buildBytes32(List<int> list, int start) {
  if(list.length - start < 4) {
    return -1;
  }
  int byte0 = list[start] & 0xFF;
  int byte1 = list[start + 1] & 0xFF;
  int byte2 = list[start + 2] & 0xFF;
  int byte3 = list[start + 3] & 0xFF;
  int result = (byte0 << 24) + (byte1 << 16) + (byte2 << 8) + byte3;
  return result;
}

int buildBytes16(List<int> list, int start) {
  if(list.length - start < 2) {
    return -1;
  }
  int byte0 = list[start] & 0xFF;
  int byte1 = list[start + 1] & 0xFF;
  int result = (byte0 << 8) + byte1;
  return result;
}

int buildBytes8(List<int> list, int start) {
  if(list.length - start < 1) {
    return -1;
  }
  return list[start] & 0xFF;
}