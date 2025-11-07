import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'media_viewer.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;

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

// --- 클래스 외부로 이동: 작업 디렉토리 ---
final String WORK_DIR_NAME = 'flutter_camera_work';
Future<Directory> getWorkDirectory() async {
  final appDir = await getApplicationDocumentsDirectory();
  final workDir = Directory('${appDir.path}/$WORK_DIR_NAME');
  if (!await workDir.exists()) {
    await workDir.create(recursive: true);
  }
  return workDir;
}

enum CaptureMode { photo, video }

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // 촬영 타이머 버튼 위젯 (클래스 메서드로 이동)
  Widget _buildShotTimerButton(int seconds, String label) {
    final bool selected = _shotTimerSeconds == seconds;
    return GestureDetector(
      onTap: _isShotCountingDown
          ? null
          : () {
              setState(() {
                _shotTimerSeconds = seconds;
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withAlpha((0.18 * 255).round())
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.white : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  // --- 화질/해상도 및 그리드 토글 상태 ---
  ResolutionPreset _resolutionPreset = ResolutionPreset.high;
  bool _showGrid = true;
  // --- 촬영 타이머 상태 ---
  int _shotTimerSeconds = 0; // 0=off, 3, 5, 10
  int _shotCountdown = 0;
  Timer? _shotCountdownTimer;
  bool get _isShotCountingDown => _shotCountdown > 0;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  CameraController? _controller;
  double _currentZoom = 1.0;
  double _maxZoom = 1.0;
  double _minZoom = 1.0;
  List<CameraDescription>? cameras;
  bool _isCameraInitialized = false;
  FlashMode _flashMode = FlashMode.off;
  int _currentCameraIndex = 0;
  File? _lastImage;
  final GlobalKey _previewKey = GlobalKey();
  bool _isFlashEffect = false;
  Timer? _flashTimer;
  CaptureMode _captureMode = CaptureMode.photo;
  bool _isRecording = false;
  bool _isSoundOn = true; // Default sound setting
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 권한 요청 후 카메라 초기화 및 동시성 제한 업데이트
    // 권한 요청 후 카메라 초기화
    _requestAllPermissions().then((granted) async {
      if (granted && mounted) {
        // 카메라 목록 가져오기
        try {
          cameras = await availableCameras();
        } catch (e) {
          debugPrint('Error getting cameras: $e');
        }
        _initializeCamera();
        _loadLastImage();
        _loadSoundSetting();
      }
    });
  }

  Future<bool> _requestAllPermissions() async {
    // 카메라 및 마이크 권한 요청
    final cameraStatus = await Permission.camera.request();
    final microphoneStatus = await Permission.microphone.request();

    final granted = cameraStatus.isGranted && microphoneStatus.isGranted;

    if (!granted && mounted) {
      // Removed snackbar message
    }

    return granted;
  }

  @override
  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
      _flashTimer?.cancel(); // 타이머 해제
      _flashTimer = null; // 타이머 참조 제거
      _controller?.dispose();
      _audioPlayer.dispose(); // Dispose audio player
    } catch (e) {
      debugPrint('Error during dispose: $e');
    } finally {
      super.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      if (state == AppLifecycleState.paused && _isRecording) {
        _stopRecording();
      }
    } catch (e) {
      debugPrint('Error during lifecycle state change: $e');
    }
  }

  void _setupCameraCallbacks() {
    _controller?.addListener(() {
      if (!mounted) return;

      if (_controller!.value.hasError) {
        debugPrint(
          'Camera error detected: ${_controller!.value.errorDescription}',
        );
        _disposeCamera();
      }

      setState(() {});
    });
  }

  Future<void> _initializeCamera() async {
    try {
      if (cameras == null || cameras!.isEmpty) {
        debugPrint('No cameras available.');
        return;
      }

      _controller = CameraController(
        cameras![_currentCameraIndex],
        _resolutionPreset,
      );
      _setupCameraCallbacks();
      await _controller?.initialize();

      if (!mounted) return;

      // 줌 레벨 설정
      _maxZoom = await _controller!.getMaxZoomLevel();
      _minZoom = await _controller!.getMinZoomLevel();

      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      _disposeCamera(); // Ensure cleanup on failure
    }
  }

  void _disposeCamera() {
    _controller?.dispose();
    _controller = null;
    setState(() {
      _isCameraInitialized = false;
    });
  }

  Future<void> _loadLastImage() async {
    final Directory workDir = await getWorkDirectory();
    if (await workDir.exists()) {
      // 비동기적으로 파일 목록을 읽고 수정시간을 비동기적으로 가져옵니다.
      final files = await workDir
          .list()
          .where(
            (e) =>
                e is File &&
                (e.path.endsWith('.jpg') || e.path.endsWith('.mp4')),
          )
          .map((e) => e as File)
          .toList();
      if (files.isNotEmpty) {
        final entries = await Future.wait(
          files.map((f) async {
            final t = await f.lastModified();
            return {'file': f, 'time': t};
          }),
        );
        entries.sort(
          (a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime),
        );
        setState(() {
          _lastImage = entries.first['file'] as File;
          if (_lastImage!.path.toLowerCase().endsWith('.mp4')) {
            vt.VideoThumbnail.thumbnailData(
              video: _lastImage!.path,
              imageFormat: vt.ImageFormat.JPEG,
              maxWidth: 128,
              quality: 25,
            ).then((data) {
              if (data != null && mounted) {
                // Preview bytes generated (can be used if needed)
              }
            });
          }
        });
      }
    }
  }

  Future<void> _playShutterSound() async {
    if (_isSoundOn) {
      await _audioPlayer.play(AssetSource('shutter.mp3'));
    }
  }

  Future<void> _playSound(String assetName) async {
    try {
      await _audioPlayer.play(AssetSource(assetName));
    } catch (e) {
      debugPrint('Error playing sound: $e');
      _audioPlayer.release(); // Ensure resources are released in case of error
    }
  }

  Future<void> _toggleSound() async {
    setState(() {
      _isSoundOn = !_isSoundOn;
    });
    // Save the sound setting persistently
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isSoundOn', _isSoundOn);
  }

  Future<void> _loadSoundSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isSoundOn = prefs.getBool('isSoundOn') ?? true; // Default to true
      });
    } catch (e) {
      debugPrint('Error loading sound settings: $e');
    }
  }

  Future<void> _takePicture() async {
    if (!_controller!.value.isInitialized) return;
    if (_controller!.value.isTakingPicture) return;
    try {
      await _playShutterSound();
      // Capture a quick preview snapshot to show immediately while the
      // takePicture() call writes to disk. We wrap CameraPreview in a
      // RepaintBoundary and use toImage to get an in-memory PNG.
      try {
        final boundary =
            _previewKey.currentContext?.findRenderObject()
                as RenderRepaintBoundary?;
        if (boundary != null) {
          final ui.Image image = await boundary.toImage(pixelRatio: 0.5);
          final byteData = await image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (byteData != null) {
            // Preview captured
            if (mounted) setState(() {});
          }
        }
      } catch (e) {
        debugPrint('preview capture failed: $e');
      }
      final Directory workDir = await getWorkDirectory();
      final String filePath =
          '${workDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final XFile file = await _controller!.takePicture();
      await file.saveTo(filePath);
      debugPrint('Photo saved to: $filePath');
      if (mounted) {
        setState(() {
          _isFlashEffect = true;
        });
      }
      _flashTimer?.cancel();
      _flashTimer = Timer(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        setState(() {
          _isFlashEffect = false;
        });
      });
      _lastImage = File(filePath);
      if (mounted) setState(() {});
      await _loadLastImage();
    } catch (e) {
      debugPrint('$e');
    }
  }

  void _onShotButtonPressed() {
    if (_isShotCountingDown) return; // 중복 방지
    if (_shotTimerSeconds == 0) {
      _takePicture();
    } else {
      setState(() {
        _shotCountdown = _shotTimerSeconds;
      });
      _shotCountdownTimer?.cancel();
      _shotCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          _shotCountdown--;
        });
        if (_shotCountdown <= 0) {
          timer.cancel();
          _shotCountdownTimer = null;
          _takePicture();
        }
      });
    }
  }

  Future<void> _startRecording() async {
    if (!_controller!.value.isInitialized) return;
    if (_isRecording) return;
    try {
      // Play start recording sound
      await _playSound('beep1.mp3');

      // 마이크 권한 확인
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final result = await Permission.microphone.request();
        if (!result.isGranted) {
          if (mounted) {
            // Removed snackbar message
          }
          return;
        }
      }
      try {
        await _controller!.startVideoRecording();
        if (mounted) {
          setState(() {
            _isRecording = true;
            _recordingDuration = Duration.zero;
          });
          _recordingTimer?.cancel();
          _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) {
              setState(() {
                _recordingDuration += const Duration(seconds: 1);
              });
            }
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('동영상 촬영을 시작할 수 없습니다: $e')));
        }
      }
    } catch (e) {
      if (mounted) {
        // Removed snackbar message
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_controller!.value.isInitialized) {
      debugPrint('Stop recording failed: Camera is not initialized.');
      return;
    }
    if (!_isRecording) {
      debugPrint('Stop recording failed: Not currently recording.');
      return;
    }
    try {
      // Play stop recording sound
      await _playSound('beep2.mp3');

      final XFile recorded = await _controller!.stopVideoRecording();
      debugPrint('Recording stopped successfully. File path: ${recorded.path}');

      final recordedFile = File(recorded.path);
      final exists = await recordedFile.exists();
      if (!exists) {
        debugPrint('Recorded file does not exist.');
        return;
      }

      final Directory workDir = await getWorkDirectory();
      final String targetPath =
          '${workDir.path}/${DateTime.now().millisecondsSinceEpoch}.mp4';

      try {
        await recordedFile.copy(targetPath);
        debugPrint('File copied to: $targetPath');
      } catch (copyError) {
        debugPrint('File copy failed: $copyError');
        try {
          await recordedFile.rename(targetPath);
          debugPrint('File renamed to: $targetPath');
        } catch (renameError) {
          debugPrint('File rename failed: $renameError');
          return;
        }
      }

      if (mounted) {
        setState(() {
          _isRecording = false;
        });
        _recordingTimer?.cancel();
        _recordingTimer = null;
        _recordingDuration = Duration.zero;
        debugPrint('Recording state updated to false.');
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) {
      return '${twoDigits(h)}:${twoDigits(m)}:${twoDigits(s)}';
    } else {
      return '${twoDigits(m)}:${twoDigits(s)}';
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

  Future<void> refreshPreviewCaptureSession() async {
    try {
      if (_controller == null || !_controller!.value.isInitialized) {
        debugPrint('Controller not initialized, attempting recovery');
        await _initializeCamera();
        return;
      }

      // 기존 세션 초기화 로직
      await _controller!.startImageStream((image) {
        debugPrint('Image stream started');
      });
    } catch (e) {
      debugPrint('Error refreshing preview capture session: $e');
      // 복구 로직
      if (_controller != null) {
        try {
          await _controller!.dispose();
        } catch (disposeError) {
          debugPrint('Controller dispose error during recovery: $disposeError');
        }
      }
      _isCameraInitialized = false;
      if (mounted) setState(() {});
    }
  }

  void _setZoom(double zoom) {
    if (_controller != null && _controller!.value.isInitialized) {
      final clampedZoom = zoom.clamp(_minZoom, _maxZoom);
      _controller!.setZoomLevel(clampedZoom);
      setState(() {
        _currentZoom = clampedZoom;
      });
    }
  }

  Future<void> _setupCamera(CameraDescription cameraDescription) async {
    _controller = CameraController(
      cameraDescription,
      _resolutionPreset,
      enableAudio: true,
    );

    try {
      await _controller!.initialize();
      _maxZoom = await _controller!.getMaxZoomLevel();
      _minZoom = await _controller!.getMinZoomLevel();
      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  void _switchCamera() {
    if (cameras != null && cameras!.isNotEmpty) {
      _currentCameraIndex = (_currentCameraIndex + 1) % cameras!.length;
      _setupCamera(cameras![_currentCameraIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 녹화 시간 카운터 UI (상단 우측)
    final Widget recordingTimerWidget =
        (_captureMode == CaptureMode.video && _isRecording)
        ? Positioned(
            top: 18,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red, width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.fiber_manual_record,
                    color: Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatDuration(_recordingDuration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();

    // 촬영 타이머 카운트다운 오버레이
    final Widget shotCountdownOverlay = _isShotCountingDown
        ? Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.35),
              child: Center(
                child: Text(
                  _shotCountdown > 0 ? '${_shotCountdown}' : '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 96,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        blurRadius: 12,
                        color: Colors.black,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    if (!_isCameraInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isCameraInitialized && _controller != null)
            GestureDetector(
              onScaleUpdate: (details) {
                if (details.pointerCount == 2) {
                  _setZoom(_currentZoom * details.scale);
                }
              },
              child: SafeArea(
                child: RepaintBoundary(
                  key: _previewKey,
                  child: CameraPreview(_controller!),
                ),
              ),
            )
          else
            Center(
              child: Text(
                '카메라 초기화 중... 또는 사용 가능한 카메라 없음',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          // 녹화 시간 카운터 UI
          recordingTimerWidget,
          // 촬영 타이머 카운트다운 오버레이
          shotCountdownOverlay,
          // 플래시 효과 오버레이
          if (_isFlashEffect)
            Positioned.fill(
              child: Container(
                color: Colors.white.withAlpha((0.85 * 255).round()),
              ),
            ),
          // 3x3 가이드라인 (토글)
          if (_showGrid)
            Positioned.fill(child: CustomPaint(painter: GridPainter())),
          // 상단 컨트롤
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _flashMode == FlashMode.off
                                ? Icons.flash_off
                                : _flashMode == FlashMode.auto
                                ? Icons.flash_auto
                                : Icons.flash_on,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: _toggleFlash,
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.flip_camera_android,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: _switchCamera,
                          tooltip: '카메라 전환 (셀카/후면)',
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // 해상도 선택 드롭다운
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: DropdownButton<ResolutionPreset>(
                            value: _resolutionPreset,
                            dropdownColor: Colors.black87,
                            underline: SizedBox.shrink(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            icon: const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.white,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: ResolutionPreset.low,
                                child: Text('SD'),
                              ),
                              DropdownMenuItem(
                                value: ResolutionPreset.medium,
                                child: Text('HD'),
                              ),
                              DropdownMenuItem(
                                value: ResolutionPreset.high,
                                child: Text('FHD'),
                              ),
                              DropdownMenuItem(
                                value: ResolutionPreset.veryHigh,
                                child: Text('QHD'),
                              ),
                              DropdownMenuItem(
                                value: ResolutionPreset.ultraHigh,
                                child: Text('UHD'),
                              ),
                              DropdownMenuItem(
                                value: ResolutionPreset.max,
                                child: Text('MAX'),
                              ),
                            ],
                            onChanged: (v) async {
                              if (v != null && v != _resolutionPreset) {
                                setState(() {
                                  _isCameraInitialized = false;
                                  _resolutionPreset = v;
                                });
                                await _setupCamera(
                                  cameras![_currentCameraIndex],
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 그리드 토글 버튼
                        IconButton(
                          icon: Icon(
                            _showGrid ? Icons.grid_on : Icons.grid_off,
                            color: Colors.white,
                            size: 26,
                          ),
                          tooltip: '그리드',
                          onPressed: () {
                            setState(() {
                              _showGrid = !_showGrid;
                            });
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            _isSoundOn ? Icons.volume_up : Icons.volume_off,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: _toggleSound,
                        ),
                        const SizedBox(width: 8),
                        // 줌 배지
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${_currentZoom.toStringAsFixed(1)}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 하단 컨트롤
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 줌 슬라이더
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.zoom_out,
                        color: Colors.white54,
                        size: 20,
                      ),
                      Expanded(
                        child: Slider(
                          value: _currentZoom,
                          min: _minZoom,
                          max: _maxZoom,
                          onChanged: (v) => _setZoom(v),
                          activeColor: Colors.white,
                          inactiveColor: Colors.white24,
                        ),
                      ),
                      const Icon(
                        Icons.zoom_in,
                        color: Colors.white54,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                // 촬영 타이머 선택 버튼
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildShotTimerButton(0, 'OFF'),
                      const SizedBox(width: 8),
                      _buildShotTimerButton(3, '3s'),
                      const SizedBox(width: 8),
                      _buildShotTimerButton(5, '5s'),
                      const SizedBox(width: 8),
                      _buildShotTimerButton(10, '10s'),
                    ],
                  ),
                ),
                // 기존 하단 컨트롤 전체 복원
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha((0.72 * 255).round()),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 모드 토글 (중좌측)
                      // 모드 토글 (중좌측)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: _isShotCountingDown
                                    ? null
                                    : () {
                                        setState(() {
                                          _captureMode = CaptureMode.photo;
                                        });
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _captureMode == CaptureMode.photo
                                        ? Colors.white.withAlpha(
                                            (0.12 * 255).round(),
                                          )
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '사진',
                                    style: TextStyle(
                                      color: _captureMode == CaptureMode.photo
                                          ? Colors.white
                                          : Colors.white.withAlpha(
                                              (0.6 * 255).round(),
                                            ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _isShotCountingDown
                                    ? null
                                    : () {
                                        setState(() {
                                          _captureMode = CaptureMode.video;
                                        });
                                      },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _captureMode == CaptureMode.video
                                        ? Colors.white.withAlpha(
                                            (0.12 * 255).round(),
                                          )
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '동영상',
                                    style: TextStyle(
                                      color: _captureMode == CaptureMode.video
                                          ? Colors.white
                                          : Colors.white.withAlpha(
                                              (0.6 * 255).round(),
                                            ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // 녹화 상태 표시
                          if (_captureMode == CaptureMode.video && _isRecording)
                            Row(
                              children: const [
                                Icon(
                                  Icons.fiber_manual_record,
                                  color: Colors.red,
                                  size: 14,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  '녹화중',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      // 촬영/녹화 버튼 (중앙)
                      GestureDetector(
                        onTap: _isShotCountingDown
                            ? null
                            : () {
                                if (_captureMode == CaptureMode.photo) {
                                  _onShotButtonPressed();
                                } else {
                                  if (_isRecording) {
                                    _stopRecording();
                                  } else {
                                    _startRecording();
                                  }
                                }
                              },
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _captureMode == CaptureMode.photo
                                ? Colors.white
                                : (_isRecording ? Colors.red : Colors.white),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(
                                  (0.18 * 255).round(),
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _captureMode == CaptureMode.photo
                              ? const Icon(
                                  Icons.camera_alt_rounded,
                                  color: Colors.black,
                                  size: 38,
                                )
                              : Icon(
                                  _isRecording ? Icons.stop : Icons.videocam,
                                  color: _isRecording
                                      ? Colors.white
                                      : Colors.black,
                                  size: 34,
                                ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 셀카 버튼 (중우측)
                      IconButton(
                        icon: const Icon(
                          Icons.flip_camera_android,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: _switchCamera,
                        tooltip: '카메라 전환',
                      ),
                      const SizedBox(width: 16),
                      // 갤러리 썸네일 (우측)
                      GestureDetector(
                        onTap: () async {
                          if (_lastImage == null) return;
                          try {
                            if (_controller != null &&
                                _controller!.value.isInitialized) {
                              try {
                                await _controller!.pausePreview();
                              } catch (e) {
                                debugPrint('pausePreview failed: $e');
                              }
                            }
                          } catch (_) {}
                          final appDir =
                              await getApplicationDocumentsDirectory();
                          final workDir = Directory(
                            '${appDir.path}/flutter_camera_work',
                          );
                          if (!await workDir.exists()) {
                            try {
                              if (_controller != null &&
                                  _controller!.value.isInitialized) {
                                try {
                                  await _controller!.resumePreview();
                                } catch (e) {
                                  debugPrint('resumePreview failed: $e');
                                }
                              }
                            } catch (_) {}
                            return;
                          }
                          final files = await workDir
                              .list()
                              .where(
                                (e) =>
                                    e is File &&
                                    (e.path.endsWith('.jpg') ||
                                        e.path.endsWith('.mp4')),
                              )
                              .map((e) => e as File)
                              .toList();
                          if (files.isEmpty) {
                            try {
                              if (_controller != null &&
                                  _controller!.value.isInitialized) {
                                try {
                                  await _controller!.resumePreview();
                                } catch (e) {
                                  debugPrint('resumePreview failed: $e');
                                }
                              }
                            } catch (_) {}
                            return;
                          }
                          final entries = await Future.wait(
                            files.map((f) async {
                              final t = await f.lastModified();
                              return {'file': f, 'time': t};
                            }),
                          );
                          entries.sort(
                            (a, b) => (b['time'] as DateTime).compareTo(
                              a['time'] as DateTime,
                            ),
                          );
                          final sortedFiles = entries
                              .map((e) => e['file'] as File)
                              .toList();
                          final initialIndex = sortedFiles.indexWhere(
                            (f) => f.path == _lastImage!.path,
                          );
                          final mediaFiles = sortedFiles;
                          final initialIdx = initialIndex < 0
                              ? 0
                              : initialIndex;
                          try {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MediaViewer(
                                  mediaFiles: mediaFiles,
                                  initialIndex: initialIdx,
                                ),
                              ),
                            );
                          } finally {
                            try {
                              if (_controller != null &&
                                  _controller!.value.isInitialized) {
                                try {
                                  await _controller!.resumePreview();
                                } catch (e) {
                                  debugPrint('resumePreview failed: $e');
                                }
                              }
                            } catch (_) {}
                          }
                        },
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 2.5),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.black,
                          ),
                          child: _lastImage != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(
                                        _lastImage!,
                                        width: 54,
                                        height: 54,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    if (_lastImage!.path.toLowerCase().endsWith(
                                      '.mp4',
                                    ))
                                      const Center(
                                        child: Icon(
                                          Icons.play_circle_fill,
                                          color: Colors.white70,
                                          size: 28,
                                        ),
                                      ),
                                  ],
                                )
                              : const Icon(
                                  Icons.photo,
                                  color: Colors.white,
                                  size: 32,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  } // --- 클래스 외부로 이동: 그리드 페인터 ---

  // _CameraScreenState 클래스 닫는 중괄호 추가
}
