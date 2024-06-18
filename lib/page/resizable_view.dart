import 'package:flutter/cupertino.dart';
import 'package:my_log/my_log.dart';
import '../mindeditor/setting/constants.dart';

mixin ResizableViewMixin {
  bool get expectedSmallView;
  String get loggingClassName;

  void routeIfResize(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final smallView = screenWidth <= Constants.widthThreshold;
    if(smallView != expectedSmallView) {
      MyLogger.info('$loggingClassName: change to ${smallView? 'small': 'large'} view');
      var routeName = smallView? Constants.navigatorRouteName: Constants.largeScreenViewName;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).popAndPushNamed(routeName);
        // , (route) {
        //   resizing = false;
        //   MyLogger.info('efantest: pop route=$route');
        //   return false;
        // });
      });
    }
  }
}