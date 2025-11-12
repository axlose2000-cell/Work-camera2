import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha((0.5 * 255).round())
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
  bool shouldRepaint(Object? oldDelegate) => false;
}

const String workDirName = 'flutter_camera_work';
const String trashDirName = '.trash';

enum CaptureMode { photo, video }

class CameraScreen extends StatefulWidget {
  const CameraScreen({Key? key}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // ✅ 모든 상태 변수들이 클래스 내부에 정의됨

  CameraController? _controller;
  List<CameraDescription>? cameras;
  int _currentCameraIndex = 0;

  bool _isCameraInitialized = false;
  bool _showGrid = false;
  bool _isSoundOn = true;

  FlashMode _flashMode = FlashMode.off;
  double _currentZoom = 1.0;
  final double _minZoom = 1.0;
  final double _maxZoom = 5.0;

  CaptureMode _captureMode = CaptureMode.photo;
  int _shotTimerSeconds = 0;
  int _shotCountdown = 0;
  bool get _isShotCountingDown => _shotCountdown > 0;

  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  bool _isRecording = false;

  AssetEntity? _lastAsset;

  final AudioPlayer _audioPlayer = AudioPlayer();

  NativeAd? _nativeAd;

  final String nativeAdUnitId = 'ca-app-pub-3940256099942544/2247696110';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _loadNativeAd();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        if (_isRecording) {
          _stopRecording();
        }
        _disposeCamera();
        break;
      case AppLifecycleState.resumed:
        if (!_isCameraInitialized && cameras != null && cameras!.isNotEmpty) {
          _initializeCamera();
        }
        break;
      case AppLifecycleState.detached:
        _disposeCamera();
        break;
      default:
        break;
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _updateCameraOrientation();
  }

  Future<void> _updateCameraOrientation() async {
    if (_controller == null) return;

    try {
      final orientation = MediaQuery.of(context).orientation;

      if (orientation == Orientation.portrait) {
        await _controller?.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } else {
        await _controller?.lockCaptureOrientation(
          DeviceOrientation.landscapeRight,
        );
      }
    } catch (e) {
      debugPrint('화면 회전 설정 오류: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      cameras = await availableCameras();

      if (cameras == null || cameras!.isEmpty) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('카메라 오류'),
              content: const Text('사용 가능한 카메라가 없습니다.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('확인'),
                ),
              ],
            ),
          );
        }
        return;
      }

      final CameraDescription selectedCamera = cameras![_currentCameraIndex];

      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: true,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }

      await _updateCameraOrientation();
      _loadAllFiles();
    } catch (e) {
      debugPrint('카메라 초기화 오류: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('카메라 초기화 실패'),
            content: Text('카메라를 초기화할 수 없습니다: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _disposeCamera() {
    _recordingTimer?.cancel();
    _controller?.dispose();
    _controller = null;
    if (mounted) {
      setState(() {
        _isCameraInitialized = false;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _nativeAd?.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ✅ 모든 메서드가 클래스 내부에 정의됨

  void _toggleFlash() {
    setState(() {
      _flashMode = _flashMode == FlashMode.off
          ? FlashMode.torch
          : FlashMode.off;
      _controller?.setFlashMode(_flashMode);
    });
  }

  void _switchCamera() {
    if (cameras != null && cameras!.length > 1) {
      _currentCameraIndex = (_currentCameraIndex + 1) % cameras!.length;
      _disposeCamera();
      _initializeCamera();
    }
  }

  void _toggleSound() {
    setState(() {
      _isSoundOn = !_isSoundOn;
    });
  }

  void _startRecording() {
    if (_isCameraInitialized && !_isRecording && _controller != null) {
      try {
        _controller!.startVideoRecording();
        setState(() {
          _isRecording = true;
        });
        _startRecordingTimer();
      } catch (e) {
        debugPrint('녹화 시작 오류: $e');
      }
    }
  }

  void _startRecordingTimer() {
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (
      timer,
    ) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      setState(() {
        _recordingDuration += const Duration(milliseconds: 100);
      });
    });
  }

  Future<void> _stopRecording() async {
    if (!_isCameraInitialized || _controller == null || !_isRecording) return;

    _recordingTimer?.cancel();

    try {
      final XFile file = await _controller!.stopVideoRecording();
      final File tempFile = File(file.path);

      if (!await tempFile.exists()) {
        throw Exception('비디오 파일이 생성되지 않았습니다');
      }

      final fileSize = await tempFile.length();
      if (fileSize == 0) {
        throw Exception('빈 비디오 파일입니다');
      }

      final AssetEntity? entity = await PhotoManager.editor.saveVideo(
        tempFile,
        relativePath: workDirName,
      );

      try {
        await tempFile.delete();
      } catch (e) {
        debugPrint('임시 파일 삭제 실패: $e');
      }

      _lastAsset = entity;
      _recordingDuration = Duration.zero;

      setState(() {
        _isRecording = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('비디오 저장 완료')));
      }
    } catch (e) {
      debugPrint('비디오 정지 오류: $e');
      setState(() {
        _isRecording = false;
      });
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('비디오 저장 실패'),
            content: Text('비디오를 저장할 수 없습니다: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _takePicture() async {
    if (!_isCameraInitialized || _controller == null) return;

    try {
      final XFile file = await _controller!.takePicture();
      final File tempFile = File(file.path);

      if (!await tempFile.exists()) {
        throw Exception('사진 파일이 생성되지 않았습니다');
      }

      final Uint8List bytes = await tempFile.readAsBytes();
      final AssetEntity? entity = await PhotoManager.editor.saveImage(
        bytes,
        relativePath: workDirName,
        filename: 'IMG_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      try {
        await tempFile.delete();
      } catch (e) {
        debugPrint('임시 파일 삭제 실패: $e');
      }

      _lastAsset = entity;
      setState(() {});

      if (mounted && _isSoundOn) {
        try {
          await _audioPlayer.play(AssetSource('shutter.mp3'));
        } catch (e) {
          debugPrint('셔터음 재생 실패: $e');
        }
      }
    } catch (e) {
      debugPrint('사진 촬영 오류: $e');
    }
  }

  void _onShotButtonPressed() {
    if (_captureMode == CaptureMode.photo) {
      if (_shotTimerSeconds > 0) {
        _startShotTimer();
      } else {
        _takePicture();
      }
    } else {
      if (_isRecording) {
        _stopRecording();
      } else {
        _startRecording();
      }
    }
  }

  Future<void> _startShotTimer() async {
    try {
      for (int i = _shotTimerSeconds; i > 0; i--) {
        if (!mounted) return;
        setState(() {
          _shotCountdown = i;
        });
        await Future.delayed(const Duration(seconds: 1));
      }
      if (mounted) {
        setState(() {
          _shotCountdown = 0;
        });
        _takePicture();
      }
    } catch (e) {
      debugPrint('타이머 오류: $e');
    }
  }

  void _setZoom(double zoomLevel) {
    if (_controller == null) return;
    final double newZoom = zoomLevel.clamp(_minZoom, _maxZoom);
    _controller!.setZoomLevel(newZoom);
    setState(() {
      _currentZoom = newZoom;
    });
  }

  void _loadNativeAd() {
    _nativeAd = NativeAd(
      adUnitId: nativeAdUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) {
            // 광고 로드 완료
            debugPrint('네이티브 광고 로드 완료');
          }
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('네이티브 광고 로드 실패: $error');
        },
      ),
    );
    _nativeAd!.load();
  }

  Future<void> _loadAllFiles() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth != true) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('저장소 권한이 필요합니다.')));
      }
      return;
    }

    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image | RequestType.video,
        hasAll: true,
      );

      AssetPathEntity? workAlbum;
      for (var album in albums) {
        if (album.name == workDirName) {
          workAlbum = album;
          break;
        }
      }

      if (workAlbum != null) {
        final assets = await workAlbum.getAssetListPaged(page: 0, size: 1000);
        if (mounted) {
          // 파일 로드 완료
          debugPrint('파일 로드 완료: ${assets.length}개');
        }
      }
    } catch (e) {
      debugPrint('파일 로드 오류: $e');
    }
  }

  String _formatRecordingDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isCameraInitialized && _controller != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  onScaleUpdate: (details) {
                    if (details.pointerCount == 2) {
                      _setZoom(_currentZoom * details.scale);
                    }
                  },
                  child: CameraPreview(_controller!),
                ),
                if (_showGrid)
                  Positioned.fill(child: CustomPaint(painter: GridPainter())),
                // 타이머 오버레이
                if (_isShotCountingDown)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.35),
                      child: Center(
                        child: Text(
                          '$_shotCountdown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 96,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 녹화 중 표시
                if (_isRecording)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.circle,
                            color: Colors.white,
                            size: 8,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatRecordingDuration(_recordingDuration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // 하단 컨트롤
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              icon: Icon(
                                _flashMode == FlashMode.off
                                    ? Icons.flash_off
                                    : Icons.flash_on,
                                color: Colors.white,
                              ),
                              onPressed: _toggleFlash,
                            ),
                            IconButton(
                              icon: Icon(
                                _isSoundOn ? Icons.volume_up : Icons.volume_off,
                                color: Colors.white,
                              ),
                              onPressed: _toggleSound,
                            ),
                            GestureDetector(
                              onTap: _onShotButtonPressed,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _isRecording
                                      ? Colors.red
                                      : Colors.white,
                                  border: Border.all(
                                    color: Colors.grey[400]!,
                                    width: 4,
                                  ),
                                ),
                                child: Icon(
                                  _isRecording
                                      ? Icons.stop
                                      : (_captureMode == CaptureMode.photo
                                            ? Icons.camera_alt
                                            : Icons.videocam),
                                  color: _isRecording
                                      ? Colors.white
                                      : Colors.black,
                                  size: 32,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _showGrid ? Icons.grid_on : Icons.grid_off,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _showGrid = !_showGrid;
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.flip_camera_android,
                                color: Colors.white,
                              ),
                              onPressed: _switchCamera,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    for (int i = 0; i <= 10; i++)
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _shotTimerSeconds = i;
                                          });
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _shotTimerSeconds == i
                                                ? Colors.blue
                                                : Colors.grey[700],
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            '${i}s',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SegmentedButton<CaptureMode>(
                              segments: const [
                                ButtonSegment(
                                  value: CaptureMode.photo,
                                  icon: Icon(Icons.camera_alt),
                                  label: Text('사진'),
                                ),
                                ButtonSegment(
                                  value: CaptureMode.video,
                                  icon: Icon(Icons.videocam),
                                  label: Text('비디오'),
                                ),
                              ],
                              selected: {_captureMode},
                              onSelectionChanged:
                                  (Set<CaptureMode> newSelection) {
                                    setState(() {
                                      _captureMode = newSelection.first;
                                    });
                                  },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // 갤러리 썸네일
                Positioned(
                  bottom: 100,
                  right: 16,
                  child: GestureDetector(
                    onTap: () async {
                      if (_lastAsset == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('저장된 파일이 없습니다.')),
                        );
                        return;
                      }

                      try {
                        if (_controller != null &&
                            _controller!.value.isInitialized) {
                          await _controller!.pausePreview();
                        }
                      } catch (e) {
                        debugPrint('pausePreview 오류: $e');
                      }

                      try {
                        if (mounted) {
                          Navigator.pushNamed(context, '/media_viewer');
                        }
                      } finally {
                        try {
                          if (_controller != null &&
                              _controller!.value.isInitialized) {
                            await _controller!.resumePreview();
                          }
                        } catch (e) {
                          debugPrint('resumePreview 오류: $e');
                        }
                      }
                    },
                    child: _lastAsset == null
                        ? Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white,
                                width: 2.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.black,
                            ),
                            child: const Icon(
                              Icons.photo,
                              color: Colors.white,
                              size: 32,
                            ),
                          )
                        : Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white,
                                width: 2.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.black,
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: FutureBuilder<File?>(
                                    future: _lastAsset!.file,
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData &&
                                          snapshot.data != null) {
                                        return Image.file(
                                          snapshot.data!,
                                          width: 54,
                                          height: 54,
                                          fit: BoxFit.cover,
                                        );
                                      }
                                      return Container(
                                        width: 54,
                                        height: 54,
                                        color: Colors.grey[800],
                                      );
                                    },
                                  ),
                                ),
                                if (_lastAsset!.type == AssetType.video)
                                  const Center(
                                    child: Icon(
                                      Icons.play_circle_fill,
                                      color: Colors.white70,
                                      size: 28,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
