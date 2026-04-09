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

class DragDropFeedbackStyle {
  // Shared shadow for the floating drag preview shown under the pointer.
  static const double elevation = 6.0;
  // Shared background color for drag feedback cards in navigator and editor.
  static const Color backgroundColor = Color(0xFFE3F2FD);
  // Shared border color for drag feedback cards.
  static const Color borderColor = Colors.blue;
  // Shared border width for drag feedback cards.
  static const double borderWidth = 1.0;
  // Shared corner radius for drag feedback cards.
  static const double borderRadius = 4.0;
  // Width of the navigator drag preview card.
  static const double navigatorWidth = 300.0;
  // Max width of the editor block drag preview card.
  static const double blockMaxWidth = 320.0;
  // Padding inside the navigator drag preview card.
  static const EdgeInsets navigatorPadding = EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
  // Padding inside the editor block drag preview card.
  static const EdgeInsets blockPadding = EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0);
  // Icon size used by the navigator drag preview.
  static const double navigatorIconSize = 18.0;
  // Icon color used by the navigator drag preview.
  static const Color navigatorIconColor = Color(0xFF757575);
  // Text color used by drag preview labels.
  static const Color textColor = Colors.black87;
  // Font size of the navigator drag preview title.
  static const double navigatorFontSize = 15.0;
  // Font size of the editor block drag preview title.
  static const double blockFontSize = 14.0;
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

class DragDropTargetHighlightStyle {
  // Time the highlight stays at full strength before fading (so the landing spot reads clearly).
  static const Duration holdDuration = Duration(milliseconds: 200);
  // Duration for fading drag-drop target highlight to normal style.
  static const Duration fadeDuration = Duration(milliseconds: 500);
  // Alpha for fill over content: strong enough to read as "feedback" tint but text stays legible.
  static const double fillAlpha = 0.26;
  static const Curve fadeCurve = Curves.easeOutCubic;
}
