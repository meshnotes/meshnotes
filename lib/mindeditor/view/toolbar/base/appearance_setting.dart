import 'package:flutter/material.dart';

class AppearanceSetting {
  double iconSize;
  double size;
  Color fillColor;
  Color hoverColor;
  EdgeInsets? padding;

  AppearanceSetting({
    required this.iconSize,
    required this.size,
    required this.fillColor,
    required this.hoverColor,
    this.padding,
  });
}