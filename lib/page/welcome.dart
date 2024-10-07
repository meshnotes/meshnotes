import 'dart:async';

import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';
import '../mindeditor/setting/constants.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    MyLogger.info('WelcomeView: screenWidth=$screenWidth');
    Timer(const Duration(milliseconds: 500), () {
      Navigator.of(context).pushReplacementNamed(Constants.largeScreenViewName);
    });
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Text('Mesh Note',
          style: TextStyle(
            color: Colors.black,
            fontSize: 36,
          ),
        ),
      ),
    );
  }
}