import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import 'package:google_mobile_ads/google_mobile_ads.dart';

class MediaViewer extends StatefulWidget {
  final List<AssetEntity> mediaAssets;
  final int initialIndex;

  const MediaViewer({
    super.key,
    required this.mediaAssets,
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

  static const double _thumbSize = 60.0;
  static const double _thumbSpacing = 8.0;

  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, bool> _mutedStates = {};

  late BannerAd _bannerAd;
  bool _isAdLoaded = false;

  // 💡 NEW: 파일 비동기 로딩을 위한 맵 추가
  final Map<int, Future<File?>> _fileFutures = {};

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.mediaAssets.isEmpty
        ? 0
        : widget.mediaAssets.length - 1;
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
        size: AdSize.banner,
        adUnitId: 'ca-app-pub-3940256099942544/6300978111',
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!_isAdLoaded) {
              setState(() {
                _isAdLoaded = true;
              });
            }
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

  // 💡 NEW: 미리 파일 로딩 예약
  void _preLoadFile(int index) {
    // 기존 컨트롤러 정리
    final keysToRemove = <int>[];
    _videoControllers.forEach((key, controller) {
      if ((key - index).abs() > 2) {
        controller.dispose();
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      _videoControllers.remove(key);
    }

    if (!_fileFutures.containsKey(index)) {
      final asset = widget.mediaAssets[index];
      _fileFutures[index] = asset.file;
    }
  }

  // 💡 NEW: 비디오 플레이어 초기화
  Future<void> _initializeVideoController(int index) async {
    final file = await _fileFutures[index];
    if (file != null && !_videoControllers.containsKey(index)) {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (mounted) {
        setState(() {
          _videoControllers[index] = controller;
          _mutedStates[index] = false;
        });
      }
    }
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
                itemCount: widget.mediaAssets.length,
                onPageChanged: (index) async {
                  _currentIndex = index;
                  _thumbPageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                  _preLoadFile(index);
                  _preLoadFile(index - 1);
                  _preLoadFile(index + 1);
                  await _initializeVideoController(index);
                  await _initializeVideoController(index - 1);
                  await _initializeVideoController(index + 1);
                },
                itemBuilder: (context, index) {
                  return _buildMedia(index);
                },
              ),

              // 💡 상단 헤더: _isUIVisible에 따라 표시/숨김
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _isUIVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_isUIVisible,
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
                                '${_currentIndex + 1} / ${widget.mediaAssets.length}',
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
                              final asset = widget.mediaAssets[_currentIndex];
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
                                  await PhotoManager.editor.deleteWithIds([
                                    asset.id,
                                  ]);
                                  if (mounted) {
                                    // ignore: use_build_context_synchronously
                                    Navigator.of(context).pop<String>(asset.id);
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
                              itemCount: widget.mediaAssets.length,
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
                                              // 썸네일 최적화: 캐시 우선, 이미지 리사이즈 적용
                                              () {
                                                final asset =
                                                    widget.mediaAssets[index];
                                                return Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    image: DecorationImage(
                                                      image: AssetEntityImageProvider(
                                                        asset,
                                                        thumbnailSize:
                                                            const ThumbnailSize(
                                                              120,
                                                              120,
                                                            ),
                                                      ),
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                );
                                              }(),
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
                                              if (widget
                                                      .mediaAssets[index]
                                                      .type ==
                                                  AssetType.video)
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

  // 💡 NEW: 사진 뷰 빌더
  Widget _buildPhotoView(File file) {
    return PhotoView.customChild(
      child: Image.file(file, fit: BoxFit.contain),
      onScaleEnd: (context, details, controllerValue) {
        // ... (기존 로직 유지)
      },
    );
  }

  // 💡 NEW: 미디어 빌더
  Widget _buildMedia(int index) {
    // 1. File 로딩이 예약되지 않았으면 예약
    _preLoadFile(index);

    // 2. FutureBuilder로 File 로딩 대기
    return FutureBuilder<File?>(
      future: _fileFutures[index],
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          final file = snapshot.data!;

          if (widget.mediaAssets[index].type == AssetType.image) {
            // 이미지
            return _buildPhotoView(file);
          } else if (widget.mediaAssets[index].type == AssetType.video) {
            // 비디오
            return _buildVideoPlayer(index, file);
          }
        } else if (snapshot.hasError) {
          return const Center(child: Text('미디어를 로드할 수 없습니다.'));
        }

        // 로딩 중
        return Container(
          color: Colors.black,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  // 💡 NEW: 비디오 플레이어 빌더
  Widget _buildVideoPlayer(int index, File file) {
    final controller = _videoControllers[index];
    if (controller?.value.isInitialized == true) {
      return _VideoPlayerControls(controller: controller!);
    }
    return Container(
      color: Colors.black,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _MediaPage extends StatefulWidget {
  final AssetEntity asset;
  final int index;
  final bool isUIVisible; // 💡 새로운 속성 추가
  final ValueChanged<bool> onScaleChanged; // 💡 NEW: 확대 상태 변경을 위한 콜백 추가

  const _MediaPage({
    Key? key,
    required this.asset,
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
    if (widget.asset.type != AssetType.video) return;
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
    if (widget.asset.type == AssetType.image) {
      return Center(
        child: PhotoView(
          imageProvider: AssetEntityImageProvider(widget.asset),
          minScale: PhotoViewComputedScale.contained * 0.8,
          maxScale: PhotoViewComputedScale.covered * 2,
          initialScale: PhotoViewComputedScale.contained,
          heroAttributes: PhotoViewHeroAttributes(tag: widget.asset.id),
          // 💡 NEW: 확대 상태가 변경될 때마다 부모에게 알림
          scaleStateChangedCallback: (state) {
            // 초기 상태가 아니면 확대된 것으로 간주
            final isZoomed = state != PhotoViewScaleState.initial;
            widget.onScaleChanged(isZoomed);
          },
        ),
      );
    } else if (widget.asset.type == AssetType.video) {
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
        child: Stack(
          children: [
            Center(
              child: _controller != null && _controller!.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : const CircularProgressIndicator(),
            ),
            if (_showVideoControls)
              Positioned(
                bottom: 20,
                left: 20,
                child: IconButton(
                  icon: Icon(
                    _controller!.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (_controller!.value.isPlaying) {
                      _controller!.pause();
                    } else {
                      _controller!.play();
                    }
                  },
                ),
              ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    super.dispose();
  }
}

class _VideoPlayerControls extends StatelessWidget {
  final VideoPlayerController controller;

  const _VideoPlayerControls({Key? key, required this.controller})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        VideoPlayer(controller),
        // 💡 비디오 진행 표시줄 및 음량 버튼 추가
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 💡 비디오 진행 표시줄
              VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.blueAccent,
                  bufferedColor: Colors.white70,
                  backgroundColor: Colors.white30,
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 💡 현재 시간 및 전체 시간 텍스트
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller,
                      builder: (context, value, child) {
                        final pos = value.position;
                        final dur = value.duration;
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
                  // 💡 음량 버튼
                  IconButton(
                    icon: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller,
                      builder: (context, value, child) {
                        final muted = value.volume == 0.0;
                        return Icon(
                          muted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                          size: 24,
                        );
                      },
                    ),
                    onPressed: () {
                      final newVolume = controller.value.volume == 0.0
                          ? 1.0
                          : 0.0;
                      controller.setVolume(newVolume);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
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
}
