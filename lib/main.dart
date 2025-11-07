import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'camera_screen.dart';
import 'gallery_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  static const platform = MethodChannel(
    'com.example.work_camera_gallery/activity',
  );
  String _activityType = 'camera'; // default

  @override
  void initState() {
    super.initState();
    _getActivityType();
    // Removed system sound check to avoid MissingPluginException
  }

  Future<void> _getActivityType() async {
    try {
      final String result = await platform.invokeMethod('getActivityType');
      setState(() {
        _activityType = result;
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to get activity type: '${e.message}'.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: _activityType == 'camera'
          ? const CameraScreen()
          : const GalleryScreen(),
    );
  }
}
