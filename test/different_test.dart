import 'package:mesh_note/mindeditor/view/view_helper.dart';
import 'package:test/test.dart';

void main() {
  testDifferent1();
  testDifferent2();
  testDifferent3();
  testDifferent4();
  testDifferent5();
  testDifferent6();
}

void testDifferent1() {
  test('find different', () {
    var leftString = "abc12345";
    var rightString = "abcxy45";
    var pos = 6;
    var leftDifferent = findLeftDifferent(leftString, rightString, pos - 1);
    var rightDifferent = findRightDifferent(leftString, rightString, pos);
    expect(leftDifferent, 3);
    expect(rightDifferent, 1);
  });
}

void testDifferent2() {
  test('find different 2', () {
    var leftString = "a";
    var rightString = "a12345678";
    var pos = 9;
    var leftDifferent = findLeftDifferent(leftString, rightString, pos - 1);
    var rightDifferent = findRightDifferent(leftString, rightString, pos);
    expect(leftDifferent, 1);
    expect(rightDifferent, 0);
  });
}

void testDifferent3() {
  test('find different 3', () {
    var leftString = "abcdefghijklmn";
    var rightString = "a1n";
    var pos = 2;
    var leftDifferent = findLeftDifferent(leftString, rightString, pos - 1);
    var rightDifferent = findRightDifferent(leftString, rightString, pos);
    expect(leftDifferent, 1);
    expect(rightDifferent, 1);
  });
}

void testDifferent4() {
  test('find different 4', () {
    var leftString = "abcdefghijklmn";
    var rightString = "a1n";
    var pos = 3;
    var leftDifferent = findLeftDifferent(leftString, rightString, pos - 1);
    var rightDifferent = findRightDifferent(leftString, rightString, pos);
    expect(leftDifferent, 1);
    expect(rightDifferent, 0);
  });
}

void testDifferent5() {
  test('test different 5', () {
    var leftString = "abc";
    var rightString = "abc";
    var pos = 3;
    var leftDifferent = findLeftDifferent(leftString, rightString, pos - 1);
    var rightDifferent = findRightDifferent(leftString, rightString, pos);
    expect(leftDifferent, 2);
    expect(rightDifferent, 0);
  });
}

void testDifferent6() {
  test('test different 6', () {
    var leftString = "abcd";
    var rightString = "a";
    var pos = 1;
    var leftDifferent = findLeftDifferent(leftString, rightString, pos - 1);
    var rightDifferent = findRightDifferent(leftString, rightString, pos);
    expect(leftDifferent, 0);
    expect(rightDifferent, 0);
  });
}