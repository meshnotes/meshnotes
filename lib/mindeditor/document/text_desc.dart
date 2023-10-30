
class TextDesc {
  static const String textKey = 'text';
  static const String fontSizeKey = 'size';
  static const String colorKey = 'color';
  static const String boldKey = 'bold';
  static const String italicKey = 'italic';
  static const String underlineKey = 'underline';

  static const double _defaultFontSize = 0;
  static const _defaultColor = TextColor.black;
  String text = '';
  double fontSize = _defaultFontSize;
  TextColor color = _defaultColor;
  bool isBold = false;
  bool isItalic = false;
  bool isUnderline = false;

  TextDesc();

  TextDesc clone() {
    return TextDesc()
      ..text = text
      ..fontSize = fontSize
      ..color = color
      ..isBold = isBold
      ..isItalic = isItalic
      ..isUnderline = isUnderline
    ;
  }

  TextDesc.fromJson(Map<String, dynamic> map) {
    if(map.containsKey(textKey)) {
      text = map[textKey];
    }
    if(map.containsKey(fontSizeKey)) {
      fontSize = map[fontSizeKey];
    }
    if(map.containsKey(colorKey)) {
      var c = map[colorKey];
      if(c < TextColor.values.length) {
        color = TextColor.values[c];
      }
    }
    if(map.containsKey(boldKey)) {
      isBold = map[boldKey];
    }
    if(map.containsKey(italicKey)) {
      isItalic = map[italicKey];
    }
    if(map.containsKey(underlineKey)) {
      isUnderline = map[underlineKey];
    }
  }
  Map<String, dynamic> toJson() {
    Map<String, dynamic> result = {
      textKey: text
    };
    if(fontSize != _defaultFontSize) {
      result[fontSizeKey] = fontSize;
    }
    if(color != _defaultColor) {
      result[colorKey] = color;
    }
    if(isBold) {
      result[boldKey] = isBold;
    }
    if(isItalic) {
      result[italicKey] = isItalic;
    }
    if(isUnderline) {
      result[underlineKey] = isUnderline;
    }
    return result;
  }
  void setProperty(String propertyName, bool value) {
    switch(propertyName) {
      case boldKey:
        isBold = value;
        break;
      case italicKey:
        isItalic = value;
        break;
      case underlineKey:
        isUnderline = value;
        break;
    }
  }
  bool isPropertyTrue(String propertyName) {
    var m = toJson();
    if(m.containsKey(propertyName)) {
      return m[propertyName] as bool;
    }
    return false;
  }
  bool sameStyleWith(TextDesc other) {
    if(fontSize != other.fontSize) {
      return false;
    }
    if(color != other.color) {
      return false;
    }
    if(isBold != other.isBold) {
      return false;
    }
    if(isItalic != other.isItalic) {
      return false;
    }
    if(isUnderline != other.isUnderline) {
      return false;
    }
    return true;
  }
}

enum TextColor {
  red,
  blue,
  black,
  white,
  grey,
  green,
}