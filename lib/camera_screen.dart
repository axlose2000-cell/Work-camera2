import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'image_viewer.dart';
import 'dart:async';
import 'dart:io';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  bool _isCameraInitialized = false;
  FlashMode _flashMode = FlashMode.off;
  int _currentCameraIndex = 0;
  File? _lastImage;
  bool _isFlashEffect = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadLastImage();
  }

  Future<void> _initializeCamera() async {
    cameras = await availableCameras();
    if (cameras!.isNotEmpty) {
      await _setupCamera(cameras![_currentCameraIndex]);
    }
  }

  Future<void> _setupCamera(CameraDescription camera) async {
    await _controller?.dispose(); // 기존 컨트롤러 dispose
    _controller = CameraController(camera, ResolutionPreset.high);
    await _controller!.initialize();
    await _controller!.setFlashMode(_flashMode);
    setState(() {
      _isCameraInitialized = true;
    });
  }

  Future<void> _loadLastImage() async {
    final Directory appDir = await getApplicationDocumentsDirectory();
    final Directory workDir = Directory('${appDir.path}/flutter_camera_work');
    if (await workDir.exists()) {
      final List<FileSystemEntity> files = workDir.listSync();
      final List<File> imageFiles = files
          .whereType<File>()
          .where((file) => file.path.endsWith('.jpg'))
          .toList();
      if (imageFiles.isNotEmpty) {
        // 가장 최근 파일 (수정 시간으로)
        imageFiles.sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );
        setState(() {
          _lastImage = imageFiles.first;
        });
      }
    }
  }

  Future<void> _takePicture() async {
    if (!_controller!.value.isInitialized) return;
    if (_controller!.value.isTakingPicture) return;

    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final Directory workDir = Directory('${appDir.path}/flutter_camera_work');
      if (!await workDir.exists()) {
        await workDir.create(recursive: true);
      }
      final String filePath =
          '${workDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final XFile file = await _controller!.takePicture();
      await file.saveTo(filePath);
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text('사진이 저장되었습니다')),
      // );
      setState(() {
        _isFlashEffect = true;
      });
      Timer(const Duration(milliseconds: 200), () {
        setState(() {
          _isFlashEffect = false;
        });
      });
      await _loadLastImage(); // 갤러리 썸네일 업데이트
    } catch (e) {
      print(e);
    }
  }

  void _toggleFlash() {
    setState(() {
      switch (_flashMode) {
        case FlashMode.off:
          _flashMode = FlashMode.auto;
          break;
        case FlashMode.auto:
          _flashMode = FlashMode.always;
          break;
        case FlashMode.always:
          _flashMode = FlashMode.off;
          break;
        default:
          _flashMode = FlashMode.off;
      }
    });
    _controller?.setFlashMode(_flashMode);
  }

  void _switchCamera() async {
    if (cameras!.length > 1) {
      _currentCameraIndex = (_currentCameraIndex + 1) % cameras!.length;
      await _setupCamera(cameras![_currentCameraIndex]);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          CameraPreview(_controller!),
          // 플래시 효과 오버레이
          if (_isFlashEffect) Container(color: Colors.white.withOpacity(0.8)),
          // 가이드라인 오버레이
          CustomPaint(size: Size.infinite, painter: GridPainter()),
          // 상단 컨트롤
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 플래시 토글
                IconButton(
                  icon: Icon(
                    _flashMode == FlashMode.off
                        ? Icons.flash_off
                        : _flashMode == FlashMode.auto
                        ? Icons.flash_auto
                        : Icons.flash_on,
                    color: Colors.white,
                  ),
                  onPressed: _toggleFlash,
                ),
                // 해상도 선택 (간단히 텍스트로 표시)
                const Text('HD', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          // 하단 컨트롤
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withOpacity(0.7),
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 갤러리 썸네일
                  GestureDetector(
                    // 썸네일 탭 시 전체 이미지와 인덱스를 넘겨줌
                    onTap: () {
                      if (_lastImage != null) {
                        // 앱 전용 폴더에서 모든 이미지 파일을 불러옴
                        getApplicationDocumentsDirectory().then((appDir) {
                          final workDir = Directory(
                            '${appDir.path}/flutter_camera_work',
                          );
                          if (workDir.existsSync()) {
                            final files = workDir
                                .listSync()
                                .whereType<File>()
                                .where((file) => file.path.endsWith('.jpg'))
                                .toList();
                            files.sort(
                              (a, b) => b.lastModifiedSync().compareTo(
                                a.lastModifiedSync(),
                              ),
                            );
                            final initialIndex = files.indexWhere(
                              (f) => f.path == _lastImage!.path,
                            );
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ImageViewer(
                                  images: files,
                                  initialIndex: initialIndex < 0
                                      ? 0
                                      : initialIndex,
                                ),
                              ),
                            );
                          }
                        });
                      }
                    },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _lastImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.file(
                                _lastImage!,
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(Icons.photo, color: Colors.white),
                    ),
                  ),
                  // 촬영 버튼
                  GestureDetector(
                    onTap: _takePicture,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: const Icon(
                        Icons.camera,
                        color: Colors.black,
                        size: 40,
                      ),
                    ),
                  ),
                  // 카메라 전환
                  IconButton(
                    icon: const Icon(
                      Icons.flip_camera_android,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: _switchCamera,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1;

    // 수직선
    canvas.drawLine(
      Offset(size.width / 3, 0),
      Offset(size.width / 3, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(2 * size.width / 3, 0),
      Offset(2 * size.width / 3, size.height),
      paint,
    );

    // 수평선
    canvas.drawLine(
      Offset(0, size.height / 3),
      Offset(size.width, size.height / 3),
      paint,
    );
    canvas.drawLine(
      Offset(0, 2 * size.height / 3),
      Offset(size.width, 2 * size.height / 3),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// ImageViewer는 image_viewer.dart에서 import하여 사용합니다.
