import 'dart:ui' as ui;

class Device {
  double safeWidth = 0;
  double safeHeight = 0;
  double physicalWidth = 0;
  double physicalHeight = 0;
  double logicalWidth = 0;
  double logicalHeight = 0;

  double paddingLeft = 0;
  double paddingRight = 0;
  double paddingTop = 0;
  double paddingBottom = 0;

  double pixelRatio = 0;

  init() {
    pixelRatio = ui.window.devicePixelRatio;

    //Size in physical pixels
    var physicalScreenSize = ui.window.physicalSize;
    physicalWidth = physicalScreenSize.width;
    physicalHeight = physicalScreenSize.height;

    //Size in logical pixels
    var logicalScreenSize = ui.window.physicalSize / pixelRatio;
    logicalWidth = logicalScreenSize.width;
    logicalHeight = logicalScreenSize.height;

    //Padding in physical pixels
    var padding = ui.window.padding;

    //Safe area paddings in logical pixels
    paddingLeft = padding.left / ui.window.devicePixelRatio;
    paddingRight = padding.right / ui.window.devicePixelRatio;
    paddingTop = padding.top / ui.window.devicePixelRatio;
    paddingBottom = padding.bottom / ui.window.devicePixelRatio;

    //Safe area in logical pixels
    safeWidth = logicalWidth - paddingLeft - paddingRight;
    safeHeight = logicalHeight - paddingTop - paddingBottom;
  }
}