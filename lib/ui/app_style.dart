import 'package:flutter/material.dart';

class DragDropStyle {
  // Color of the drop indicator line shown between items.
  static const Color lineColor = Colors.blueGrey;
  // Thickness of the drop indicator line.
  static const double lineHeight = 3.0;
  // Length of each leading segment in navigator drop indicators.
  static const double navigatorLineSegmentWidth = 15.0;
  // Length of each leading segment in editor drop indicators.
  static const double editorLineSegmentWidth = 12.0;
  // Offset applied to navigator drag feedback so the drop line stays visible.
  static const Offset navigatorFeedbackOffset = Offset(0, -50);
  // Offset applied to editor drag feedback so the dragged preview does not cover the target line.
  static const Offset editorFeedbackOffset = Offset(0, -36);
}

class DragDropPlaceHolderStyle {
  // Border color of the in-place dragged source item.
  static const Color borderColor = Color(0xFFBDBDBD);
  // Background color of the in-place dragged source item.
  static const Color backgroundColor = Color(0xFFF5F5F5);
  // Corner radius of the dragged source placeholder.
  static const double borderRadius = 6.0;
  // Opacity applied to the placeholder content so text and icons look faded.
  static const double contentOpacity = 0.58;
  // Duration of the placeholder fade transition.
  static const Duration fadeDuration = Duration(milliseconds: 120);
}

class DragDropTargetFlashStyle {
  // Border color of the post-drop flash highlight.
  static const Color borderColor = Color(0xFFFFB74D);
  // Background color of the post-drop flash highlight.
  static const Color backgroundColor = Color(0xFFFFF3E0);
  // Corner radius of the post-drop flash highlight.
  static const double borderRadius = 6.0;
  // Interval between flash frames after a successful move.
  static const Duration flashInterval = Duration(milliseconds: 140);
}
