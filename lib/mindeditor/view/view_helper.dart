import 'dart:math' as math;

int findLeftDifferent(String left, String right, int pos) {
  pos = math.max(0, pos);
  var minLength = math.min(left.length, right.length);
  minLength = math.min(minLength, pos);
  // 从左边开始，找到相同字符数量
  for(var idx = 0; idx < minLength; idx++) {
    if(left[idx] != right[idx]) {
      return idx;
    }
  }
  return minLength;
}

int findRightDifferent(String left, String right, int pos) {
  pos = math.max(0, pos);
  var limit = right.length - pos;
  limit = math.min(limit, left.length);
  if(limit <= 0) {
    return 0;
  }
  var leftEnd = left.length - 1;
  var rightEnd = right.length - 1;
  // 从右边开始，找到相同字符数量
  int count;
  for(count = 0; count < limit; count++) {
    if(left[leftEnd - count] != right[rightEnd - count]) {
      break;
    }
  }
  return count;
}