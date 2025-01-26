import 'package:flutter/material.dart';
import 'mesh_app.dart';

class SplashPage extends StatefulWidget {
  final Future<void> Function() onInit;
  const SplashPage({super.key, required this.onInit});

  @override
  State<SplashPage> createState() => _SplashPageState();
}


class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late Future<bool> initialization;
  bool initialized = false;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    initialization = _initialization();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<bool> _initialization() async {
    if(initialized) {
      return true;
    }
    // ignore: avoid_print
    print('Initializing...'); // log module is not initialized yet
    
    final futures = await Future.wait([
      widget.onInit().then((_) => true),
      Future.delayed(const Duration(seconds: 1)),  // Make sure to show at least 1 second
    ]);
    
    initialized = futures[0];
    return initialized;
  }

  @override
  Widget build(BuildContext context) {
    final future = FutureBuilder<bool>(
      future: initialization,
      builder: (context, snapshot) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 800),
          child: (snapshot.connectionState == ConnectionState.done && snapshot.data == true)
              ? const MeshApp()
              : Scaffold(
                  key: const ValueKey('splash'),
                  backgroundColor: Colors.white,
                  body: Center(
                    child: Image.asset('assets/splash.png'),
                  ),
                ),
        );
      },
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: future,
    );
  }
}


