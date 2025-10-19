import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'image_viewer.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<File> _images = [];
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadImages();
    _loadBannerAd();
  }

  Future<void> _loadImages() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory workDir = Directory('${appDir.path}/flutter_camera_work');
    if (await workDir.exists()) {
      final List<FileSystemEntity> files = workDir.listSync();
      final List<File> imageFiles = files
          .whereType<File>()
          .where((file) => file.path.endsWith('.jpg'))
          .toList();
      // 수정 시간으로 정렬 (최신이 먼저)
      imageFiles.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
      setState(() {
        _images = imageFiles;
      });
    }
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111', // Test ID
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    _bannerAd!.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('업갤 - 업무갤러리'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadImages),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4.0,
                mainAxisSpacing: 4.0,
              ),
              itemCount: _images.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ImageViewer(images: _images, initialIndex: index),
                      ),
                    );
                  },
                  child: Image.file(_images[index], fit: BoxFit.cover),
                );
              },
            ),
          ),
          if (_isAdLoaded)
            Container(
              alignment: Alignment.center,
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
    );
  }
}
