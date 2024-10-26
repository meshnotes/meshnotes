import 'package:flutter/material.dart';

class AppearanceSetting {
  double iconSize;
  double size;
  Color fillColor;
  Color hoverColor;
  Color disabledColor;
  EdgeInsets? padding;

  AppearanceSetting({
    required this.iconSize,
    required this.size,
    required this.fillColor,
    required this.hoverColor,
    required this.disabledColor,
    this.padding,
  });
}