import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Clean single-file mixed media viewer.
/// - Accepts a list of [File] objects (images or .mp4 videos).
/// - Swipe through media with [PageView].
/// - Images use [PhotoView] (pinch/zoom).
/// - Videos use [VideoPlayer] with a play overlay and scrubbing indicator.
/// - Bottom linear progress indicator and a horizontal thumbnail strip.
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
  late final PageController _pageController;
  late final ScrollController _thumbScrollController;
  late int _currentIndex;
  // thumbnail carousel uses ScrollController now
  final double _thumbSize = 64.0;
  final Map<String, String> _thumbCache = {}; // sourcePath -> thumbnailPath
  final Map<String, Future<String?>?> _thumbGenerationFutures = {};
  final Map<int, VideoPlayerController> _videoControllers = {};
  // Initialize _mutedStates as a Map
  Map<int, bool> _mutedStates = {};
  // limit concurrent video initialize operations (set to 1 to avoid decoder resource contention)
  final int _maxConcurrentInits = 1;
  int _currentInits = 0;
  // queue removed; using simple semaphore-style counter instead

  late BannerAd _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.mediaFiles.isEmpty
        ? 0
        : widget.mediaFiles.length - 1;
    // use the initialIndex passed by the caller (clamped)
    _currentIndex = widget.initialIndex.clamp(0, maxIndex).toInt();
    _pageController = PageController(initialPage: _currentIndex);
    _thumbScrollController = ScrollController();
    // prefetch thumbnails for improved UX
    prefetchThumbnails();
    // initialize banner ad
    _loadAd();
    // Scroll thumbnail to center after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollThumbToCenter(_currentIndex);
    });
  }

  void _loadAd() {
    try {
      _bannerAd = BannerAd(
        adUnitId: 'ca-app-pub-3940256099942544/6300978111', // Test ID
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
      // Handle ad loading error
    }
  }

  void prefetchThumbnails() {
    for (final file in widget.mediaFiles) {
      if (file.path.toLowerCase().endsWith('.mp4')) {
        _thumbGenerationFutures[file.path] = _generateThumbnail(file.path);
      } else {
        // 이미지 파일은 썸네일 생성에서 제외
        _thumbCache[file.path] = file.path;
      }
    }
  }

  Future<String?> _generateThumbnail(String videoPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final thumbPath = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: tempDir.path,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 64,
        quality: 75,
      );
      if (thumbPath != null) {
        _thumbCache[videoPath] = thumbPath;
      }
      return thumbPath;
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
      return null;
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });

    // Scroll the thumbnail to the center
    _scrollThumbToCenter(index);

    // Clean up controllers far from the current index
    _cleanupDistantControllers(index);

    // Initialize new controller if not already initialized
    if (!_videoControllers.containsKey(index)) {
      _initializeVideoController(index);
    }
  }

  void _scrollThumbToCenter(int index) {
    if (!_thumbScrollController.hasClients) return;

    final thumbWidth = _thumbSize + 8.0; // itemExtent
    final screenWidth = MediaQuery.of(context).size.width;

    // 선택된 썸네일의 좌측 시작 위치
    final thumbLeft = index * thumbWidth;
    // 선택된 썸네일의 테두리 중심 위치 (썸네일 중심 + 테두리 반폭)
    final thumbCenter = thumbLeft + (_thumbSize / 2) + 1.5; // 테두리 너비 3의 절반
    // 스크롤 위치: 테두리 중심이 화면 중앙에 오도록 조정
    final scrollPosition = thumbCenter - (screenWidth / 2);

    // 스크롤 범위를 동적으로 계산
    final minScrollExtent = _thumbScrollController.position.minScrollExtent;
    final maxScrollExtent = _thumbScrollController.position.maxScrollExtent;

    // 첫 번째와 마지막 썸네일의 경우 테두리가 중앙에 위치하도록 클램핑
    final clampedScrollPosition = scrollPosition.clamp(
      minScrollExtent,
      maxScrollExtent,
    );

    _thumbScrollController.animateTo(
      clampedScrollPosition,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _cleanupDistantControllers(int currentIndex) {
    final indicesToRemove = <int>[];

    _videoControllers.forEach((idx, ctrl) {
      // Remove controllers more than 2 pages away
      if ((idx - currentIndex).abs() > 2) {
        indicesToRemove.add(idx);
      }
    });

    for (final idx in indicesToRemove) {
      debugPrint('Disposing controller at index $idx');
      try {
        final ctrl = _videoControllers[idx];
        if (ctrl != null) {
          if (ctrl.value.isInitialized) {
            ctrl.pause();
          }
          ctrl.dispose();
        }
      } catch (e) {
        debugPrint('Error disposing controller at index $idx: $e');
      }
      _videoControllers.remove(idx);
    }
  }

  // void _onThumbPageChanged(int index) {
  //   // Add logic for thumbnail page change if needed
  // }

  void _onChildControllerChanged(int index, VideoPlayerController? controller) {
    // Update logic to handle controller changes
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
    // Your build implementation here (already present below in your code)
    // Just ensure this method exists in the class.
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: widget.mediaFiles.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final file = widget.mediaFiles[index];
                final isVideo = file.path.toLowerCase().endsWith('.mp4');
                return _MediaPage(
                  file: file,
                  isVideo: isVideo,
                  index: index,
                  currentIndex: _currentIndex,
                  onController: _onChildControllerChanged,
                );
              },
            ),
            // Top bar: back + index + delete
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_currentIndex + 1} / ${widget.mediaFiles.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // 삭제 버튼
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    tooltip: '삭제',
                    onPressed: () async {
                      final file = widget.mediaFiles[_currentIndex];
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('삭제 확인'),
                          content: const Text('이 미디어 파일을 삭제하시겠습니까?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('삭제'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          await file.delete();
                          if (mounted) {
                            Navigator.of(context).pop<String>(file.path);
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('삭제 실패: $e')),
                            );
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            // Bottom: progress + thumbnails
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.only(
                  bottom: 12,
                  left: 8,
                  right: 8,
                  top: 8,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black54],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Removed LinearProgressIndicatorhe
                    // extra padding added so thumbnails that are translatedrder.
                    // upward (lifted for center effect) don't overlap the                    // increased from 16 -> 20 to provide slightly more spacing
                    // progress indicator or hide their top border.ator's top border is clearly visible.
                    // increased from 16 -> 20 to provide slightly more spacingt: 20),
                    // so the progress indicator's top border is clearly visible.
                    const SizedBox(height: 20),
                    SizedBox(
                      height: _thumbSize + 12,
                      child: ListView.builder(
                        controller: _thumbScrollController,
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.mediaFiles.length,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.symmetric(
                          horizontal:
                              (MediaQuery.of(context).size.width -
                                  _thumbSize -
                                  6) /
                              2,
                        ),
                        itemExtent: _thumbSize + 8, // 각 항목의 정확한 너비 설정
                        itemBuilder: (context, idx) {
                          final file = widget.mediaFiles[idx];
                          final isVideo = file.path.toLowerCase().endsWith(
                            '.mp4',
                          );

                          Widget thumbChild;
                          if (isVideo) {
                            thumbChild = Center(
                              child: Icon(
                                Icons.play_arrow,
                                color: Colors.white70,
                              ),
                            );
                          } else {
                            thumbChild = Image.file(file, fit: BoxFit.cover);
                          }

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _currentIndex = idx;
                              });
                              _pageController.animateToPage(
                                idx,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                              _scrollThumbToCenter(idx);
                            },
                            child: Container(
                              width: _thumbSize,
                              height: _thumbSize,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: idx == _currentIndex
                                      ? Colors.white
                                      : Colors.white24,
                                  width: idx == _currentIndex ? 3 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: thumbChild,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Video overlays (time label + mute toggle) - rendered above thumbnails
            Positioned(
              left: 0,
              right: 0,
              // place the time overlay above the thumbnail strip and progress area
              bottom: _thumbSize + 48,
              child: Center(
                child: Builder(
                  builder: (context) {
                    final ctrl = _currentController;
                    final currentFile = widget.mediaFiles.isNotEmpty
                        ? widget.mediaFiles[_currentIndex]
                        : null;
                    final isVideo =
                        currentFile != null &&
                        currentFile.path.toLowerCase().endsWith('.mp4');
                    if (!isVideo || ctrl == null || !ctrl.value.isInitialized) {
                      return const SizedBox.shrink();
                    }
                    final pos = ctrl.value.position;
                    final dur = ctrl.value.duration;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              right: 12,
              // align mute toggle bottom with the time overlay (just above the bottom area)
              bottom: _thumbSize + 48,
              child: Builder(
                builder: (context) {
                  final ctrl = _currentController;
                  final currentFile = widget.mediaFiles.isNotEmpty
                      ? widget.mediaFiles[_currentIndex]
                      : null;
                  final isVideo =
                      currentFile != null &&
                      currentFile.path.toLowerCase().endsWith('.mp4');
                  if (!isVideo || ctrl == null || !ctrl.value.isInitialized) {
                    return const SizedBox.shrink();
                  }
                  final muted = _mutedStates[_currentIndex] ?? false;
                  return InkWell(
                    onTap: () {
                      final newMuted = !muted;
                      _mutedStates[_currentIndex] = newMuted;
                      try {
                        ctrl.setVolume(newMuted ? 0.0 : 1.0);
                      } catch (_) {}
                      setState(() {});
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        muted ? Icons.volume_off : Icons.volume_up,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
            ),
            // Ad moved to Scaffold.bottomNavigationBar so body is inset
          ],
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
      // Dispose all video controllers to prevent memory leaks
      for (final controller in _videoControllers.values) {
        try {
          if (controller.value.isInitialized) {
            controller.pause();
          }
          controller.dispose();
        } catch (e) {
          debugPrint('Error disposing video controller: $e');
        }
      }
      _videoControllers.clear();
    } catch (e) {
      debugPrint('Error clearing video controllers: $e');
    }

    try {
      // Dispose page controllers
      _pageController.dispose();
      _thumbScrollController.dispose();
    } catch (e) {
      debugPrint('Error disposing page controllers: $e');
    }

    try {
      // Dispose banner ad
      _bannerAd.dispose();
    } catch (e) {
      debugPrint('Error disposing banner ad: $e');
    }

    super.dispose();
  }

  Future<void> _initializeVideoController(int index) async {
    // Wait if max concurrent initializations are reached
    while (_currentInits >= _maxConcurrentInits) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _currentInits++;
    final file = widget.mediaFiles[index];
    final controller = VideoPlayerController.file(file);

    try {
      await controller.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () =>
            throw TimeoutException('Video initialization timed out'),
      );

      if (mounted) {
        setState(() {
          _videoControllers[index] = controller;
        });
      }
    } catch (e) {
      debugPrint('Error initializing video at index $index: $e');
      try {
        controller.dispose();
      } catch (_) {}
    } finally {
      _currentInits--;
    }
  }
}

// Move _MediaPage to the top level
class _MediaPage extends StatefulWidget {
  final File file;
  final bool isVideo;
  final int index;
  final int currentIndex;
  final void Function(int index, VideoPlayerController? controller)?
  onController;

  const _MediaPage({
    required this.file,
    required this.isVideo,
    required this.index,
    required this.currentIndex,
    this.onController,
  });

  @override
  State<_MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<_MediaPage> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  bool _initFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      // controller resolution moved to didChangeDependencies where context is safe
      _initializeFuture = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.isVideo) return; // context is safe
    try {
      final parentState = context.findAncestorStateOfType<_MediaViewerState>();
      final parentCtrl = parentState?._videoControllers[widget.index];
      if (parentCtrl != null) {
        _controller = parentCtrl;
      } else {
        _controller ??= VideoPlayerController.file(widget.file);
      }
    } catch (_) {
      _controller ??= VideoPlayerController.file(widget.file);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 이미지 파일인 경우
    if (!widget.isVideo) {
      return GestureDetector(
        onTap: () {
          // 이미지 뷰 탭 처리
        },
        child: Center(
          child: PhotoView(
            imageProvider: FileImage(widget.file),
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 2,
            initialScale: PhotoViewComputedScale.contained,
            heroAttributes: PhotoViewHeroAttributes(tag: widget.file.path),
          ),
        ),
      );
    }

    // 동영상 파일인 경우
    return GestureDetector(
      onTap: () {
        if (!_initFailed) {
          _togglePlay();
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: _controller != null && _controller!.value.isInitialized
                ? AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  )
                : _initFailed
                ? Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '비디오를 재생할 수 없습니다.',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: () async {
                              setState(() {
                                _initFailed = false;
                              });
                              await _initController();
                              if (_initFailed && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('비디오 초기화에 실패했습니다.'),
                                  ),
                                );
                              }
                            },
                            child: const Text('재시도'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Container(color: Colors.black),
          ),
          if (!_initFailed)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _togglePlay() async {
    if (_controller == null) return;
    // initialize on demand when user attempts to play
    if (!_controller!.value.isInitialized) {
      _initializeFuture = _initController();
      await _initializeFuture;
    }
    if (_controller!.value.isPlaying) {
      await _controller!.pause();
    } else {
      await _controller!.play();
    }
  }

  Future<void> _initController() async {
    try {
      _initFailed = false;
      _controller = VideoPlayerController.file(widget.file);

      await _controller!.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('비디오 초기화 시간 초과');
        },
      );

      _controller!.setLooping(false);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error initializing VideoPlayerController: $e');
      _initFailed = true;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    try {
      _controller?.dispose();
    } catch (_) {}
    super.dispose();
  }
}
