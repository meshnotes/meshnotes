import 'dart:math' as math;

int findLeftDifferent(String left, String right, int pos) {
  pos = math.max(0, pos);
  var minLength = math.min(left.length, right.length);
  minLength = math.min(minLength, pos);
  // Find the count of same characters from left
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
  // Find the count of same characters from right
  int count;
  for(count = 0; count < limit; count++) {
    if(left[leftEnd - count] != right[rightEnd - count]) {
      break;
    }
  }
  return count;
}