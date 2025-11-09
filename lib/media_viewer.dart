import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class MediaViewer extends StatefulWidget {
  final List<File> mediaFiles;
  final int initialIndex;

  const MediaViewer({
    super.key,
    required this.mediaFiles,
    this.initialIndex = 0,
  });

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late PageController _pageController;
  late PageController _thumbPageController;
  late int _currentIndex;

  // 💡 UI 표시 상태 관리 변수 추가
  bool _isUIVisible = true;

  // 💡 현재 이미지 확대 상태 (PageView 스크롤 비활성화 제어용)
  bool _isImageZoomed = false;

  static const double _thumbSize = 60.0;
  static const double _thumbSpacing = 8.0;

  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, bool> _mutedStates = {};

  late BannerAd _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.mediaFiles.isEmpty
        ? 0
        : widget.mediaFiles.length - 1;
    _currentIndex = widget.initialIndex.clamp(0, maxIndex).toInt();

    _pageController = PageController(
      initialPage: _currentIndex,
      viewportFraction: 1.0,
    );

    _thumbPageController = PageController(
      initialPage: _currentIndex,
      viewportFraction: 0.2,
    );

    _loadAd();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeVideoController(_currentIndex);
    });
  }

  void _loadAd() {
    try {
      _bannerAd = BannerAd(
        adUnitId: 'ca-app-pub-3940256099942544/6300978111',
        request: const AdRequest(),
        size: AdSize.banner,
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
      )..load();
    } catch (e) {
      debugPrint('Ad loading error: $e');
    }
  }

  // 💡 NEW: 자식으로부터 확대 상태를 전달받아 업데이트하는 함수
  void _handleScaleChange(bool isZoomed) {
    if (_isImageZoomed != isZoomed) {
      setState(() {
        _isImageZoomed = isZoomed;
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  VideoPlayerController? get _currentController {
    if (_videoControllers.containsKey(_currentIndex)) {
      return _videoControllers[_currentIndex];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _isUIVisible = !_isUIVisible;
            });
          },
          child: Stack(
            children: [
              // 💡 메인 뷰어 PageView.builder
              PageView.builder(
                controller: _pageController,
                itemCount: widget.mediaFiles.length,
                // 💡 NEW: _isImageZoomed 상태에 따라 스크롤을 제어
                physics: _isImageZoomed
                    ? const NeverScrollableScrollPhysics() // 확대 시: 페이지 전환 비활성화 (패닝만 가능)
                    : const AlwaysScrollableScrollPhysics(), // 축소 시: 페이지 전환 활성화
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                    _isImageZoomed = false; // 💡 NEW: 페이지 넘어가면 확대 상태 초기화
                  });
                  // 💡 메인 뷰어가 변경되면 썸네일 리스트도 동기화
                  _thumbPageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                  // 💡 새 페이지의 비디오 초기화
                  _initializeVideoController(index);
                },
                itemBuilder: (context, index) {
                  final file = widget.mediaFiles[index];
                  final isVideo = file.path.toLowerCase().endsWith('.mp4');

                  // 💡 _MediaPage 위젯 사용으로 이미지/비디오 로직 분리
                  return _MediaPage(
                    file: file,
                    isVideo: isVideo,
                    index: index,
                    isUIVisible: _isUIVisible, // 💡 UI 표시 상태 전달
                    onScaleChanged: _handleScaleChange, // 💡 NEW: 콜백 전달
                  );
                },
              ),

              // 💡 상단 헤더: _isUIVisible에 따라 표시/숨김
              AnimatedOpacity(
                opacity: _isUIVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_isUIVisible,
                  child: Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.black.withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                '${_currentIndex + 1} / ${widget.mediaFiles.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                            ),
                            onPressed: () async {
                              final file = widget.mediaFiles[_currentIndex];
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete'),
                                  content: const Text('Delete this media?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(ctx).pop(true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                try {
                                  await file.delete();
                                  if (mounted) {
                                    // ignore: use_build_context_synchronously
                                    Navigator.of(
                                      context,
                                    ).pop<String>(file.path);
                                  }
                                } catch (e) {
                                  debugPrint('Delete error: $e');
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: _isUIVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_isUIVisible,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_currentController != null &&
                            _currentController!.value.isInitialized)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Builder(
                              builder: (context) {
                                final pos = _currentController!.value.position;
                                final dur = _currentController!.value.duration;
                                return Text(
                                  '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                );
                              },
                            ),
                          ),

                        if (_currentController != null &&
                            _currentController!.value.isInitialized)
                          // 💡 비디오 진행 표시줄 추가
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: VideoProgressIndicator(
                              _currentController!,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Colors.blueAccent,
                                bufferedColor: Colors.white70,
                                backgroundColor: Colors.white30,
                              ),
                            ),
                          ),

                        Container(
                          color: Colors.black.withOpacity(0.7),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: SizedBox(
                            height: _thumbSize,
                            child: PageView.builder(
                              controller: _thumbPageController,
                              itemCount: widget.mediaFiles.length,
                              onPageChanged: (index) {
                                setState(() {
                                  _currentIndex = index;
                                });
                                // 💡 하단 필름스트립이 변경되면 상단 메인 뷰어도 동기화
                                _pageController.animateToPage(
                                  index,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              },
                              itemBuilder: (context, index) {
                                // 💡 AnimatedBuilder로 부드러운 스케일 애니메이션 적용
                                return AnimatedBuilder(
                                  animation: _thumbPageController,
                                  builder: (context, child) {
                                    double scale = 1.0;
                                    try {
                                      final page =
                                          _thumbPageController.page ?? 0.0;
                                      final diff = (index - page).abs();
                                      scale =
                                          1.0 +
                                          (0.3 * (1.0 - diff.clamp(0.0, 1.0)));
                                    } catch (e) {
                                      scale = 1.0;
                                    }

                                    return Transform.scale(
                                      scale: scale,
                                      child: GestureDetector(
                                        onTap: () {
                                          _pageController.animateToPage(
                                            index,
                                            duration: const Duration(
                                              milliseconds: 300,
                                            ),
                                            curve: Curves.easeInOut,
                                          );
                                        },
                                        // 💡 Padding을 제거하고 margin으로 이동
                                        child: Container(
                                          margin: EdgeInsets.symmetric(
                                            horizontal: _thumbSpacing / 2,
                                          ),
                                          width: _thumbSize,
                                          height: _thumbSize,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              // 💡 이미지 레이어
                                              Container(
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  image: DecorationImage(
                                                    image: FileImage(
                                                      widget.mediaFiles[index],
                                                    ),
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              ),
                                              // 💡 선택 테두리 레이어
                                              Container(
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color:
                                                        index == _currentIndex
                                                        ? Colors.blueAccent
                                                        : Colors.transparent,
                                                    width: 3.0,
                                                  ),
                                                ),
                                              ),
                                              // 💡 비디오 재생 아이콘
                                              if (widget.mediaFiles[index].path
                                                  .toLowerCase()
                                                  .endsWith('.mp4'))
                                                Center(
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.black45,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    padding:
                                                        const EdgeInsets.all(4),
                                                    child: const Icon(
                                                      Icons.play_arrow,
                                                      color: Colors.white,
                                                      size: 16,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 💡 음량 조절 버튼: _isUIVisible에 따라 표시/숨김
              if (_currentController != null &&
                  _currentController!.value.isInitialized)
                AnimatedOpacity(
                  opacity: _isUIVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_isUIVisible,
                    child: Positioned(
                      right: 16,
                      bottom: _thumbSize + 50,
                      child: Builder(
                        builder: (context) {
                          final muted = _mutedStates[_currentIndex] ?? false;
                          return GestureDetector(
                            onTap: () {
                              final newMuted = !muted;
                              _mutedStates[_currentIndex] = newMuted;
                              try {
                                _currentController!.setVolume(
                                  newMuted ? 0.0 : 1.0,
                                );
                              } catch (_) {}
                              setState(() {});
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(10),
                              child: Icon(
                                muted ? Icons.volume_off : Icons.volume_up,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _isAdLoaded
          ? SizedBox(
              height: _bannerAd.size.height.toDouble(),
              width: double.infinity,
              child: AdWidget(ad: _bannerAd),
            )
          : null,
    );
  }

  @override
  void dispose() {
    try {
      for (final controller in _videoControllers.values) {
        try {
          if (controller.value.isInitialized) {
            controller.pause();
          }
          controller.dispose();
        } catch (e) {
          debugPrint('Error disposing: $e');
        }
      }
      _pageController.dispose();
      _thumbPageController.dispose();
      _bannerAd.dispose();
    } catch (e) {
      debugPrint('Dispose error: $e');
    }
    super.dispose();
  }

  Future<void> _initializeVideoController(int index) async {
    final file = widget.mediaFiles[index];
    if (!file.path.toLowerCase().endsWith('.mp4')) {
      return;
    }

    if (_videoControllers.containsKey(index)) {
      return;
    }

    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw TimeoutException('Video initialization timed out'),
      );

      // 💡 비디오 반복 재생 설정
      controller.setLooping(true);

      if (mounted) {
        setState(() {
          _videoControllers[index] = controller;
        });
      }
    } catch (e) {
      debugPrint('Error initializing video: $e');
      try {
        controller.dispose();
      } catch (_) {}
    }
  }
}

class _MediaPage extends StatefulWidget {
  final File file;
  final bool isVideo;
  final int index;
  final bool isUIVisible; // 💡 새로운 속성 추가
  final ValueChanged<bool> onScaleChanged; // 💡 NEW: 확대 상태 변경을 위한 콜백 추가

  const _MediaPage({
    Key? key,
    required this.file,
    required this.isVideo,
    required this.index,
    required this.isUIVisible, // 💡 생성자에 추가
    required this.onScaleChanged, // 💡 생성자에 추가
  }) : super(key: key);

  @override
  State<_MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<_MediaPage> {
  VideoPlayerController? _controller;

  // 💡 비디오 컨트롤 아이콘의 임시 표시 상태
  bool _showVideoControls = false;
  Timer? _controlsTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.isVideo) return;
    try {
      final parentState = context.findAncestorStateOfType<_MediaViewerState>();
      final parentCtrl = parentState?._videoControllers[widget.index];
      if (parentCtrl != null) {
        _controller = parentCtrl;
      }
    } catch (_) {}
  }

  // 💡 타이머 설정 및 해제 함수
  void _setControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 2), () {
      // 2초 후 자동 숨김
      if (mounted) {
        setState(() {
          _showVideoControls = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVideo) {
      return Center(
        child: PhotoView(
          imageProvider: FileImage(widget.file),
          minScale: PhotoViewComputedScale.contained * 0.8,
          maxScale: PhotoViewComputedScale.covered * 2,
          initialScale: PhotoViewComputedScale.contained,
          heroAttributes: PhotoViewHeroAttributes(tag: widget.file.path),
          // 💡 NEW: 확대 상태가 변경될 때마다 부모에게 알림
          scaleStateChangedCallback: (state) {
            // 초기 상태가 아니면 확대된 것으로 간주
            final isZoomed = state != PhotoViewScaleState.initial;
            widget.onScaleChanged(isZoomed);
          },
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        if (_controller != null && _controller!.value.isInitialized) {
          if (_controller!.value.isPlaying) {
            _controller!.pause();
          } else {
            _controller!.play();
          }
        }

        // 💡 탭할 때마다 아이콘을 잠시 보여주고 타이머를 시작
        if (mounted) {
          setState(() {
            _showVideoControls = true;
          });
          _setControlsTimer();
        }
      },
      child: _controller != null && _controller!.value.isInitialized
          ? AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_controller!),
                  // 💡 아이콘을 표시할 최종 조건 설정 (OR 조건)
                  Builder(
                    builder: (context) {
                      final bool shouldShowIcon =
                          widget.isUIVisible || // 1. 메인 UI가 켜져 있거나
                          !_controller!
                              .value
                              .isPlaying || // 2. 비디오가 일시 정지 상태이거나
                          _showVideoControls; // 3. 사용자가 방금 탭해서 임시로 켜진 상태일 때

                      return AnimatedOpacity(
                        // 💡 최종 조건에 따라 투명도 조절
                        opacity: shouldShowIcon ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: IgnorePointer(
                          ignoring: !shouldShowIcon, // 💡 최종 조건에 따라 터치 무시
                          child:
                              (!_controller!.value.isPlaying ||
                                  _showVideoControls)
                              ? Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black45,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  child: const Icon(
                                    Icons.play_arrow,
                                    color: Colors.white,
                                    size: 48,
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ],
              ),
            )
          : Container(
              color: Colors.black,
              child: const Center(child: CircularProgressIndicator()),
            ),
    );
  }

  @override
  void dispose() {
    _controlsTimer?.cancel(); // 💡 타이머 해제
    // 💡 부모(_MediaViewerState)에서 관리하는 컨트롤러는 부모에서만 dispose 처리
    // 자식 위젯에서 dispose() 호출 시 컨트롤러를 종료하면 안됨
    // (이미 종료된 컨트롤러를 나중에 재사용할 때 크래시 발생)
    super.dispose();
  }
}
