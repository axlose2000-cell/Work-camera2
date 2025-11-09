// Minimal gallery screen
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'dart:typed_data';

import 'media_viewer.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<File> _flat = [];
  // group keys in display order
  final List<String> _groupKeys = [];
  // map groupKey -> list of global indices into _flat
  final Map<String, List<int>> _groupIndexMap = {};

  // 💡 휴지통 기능 추가
  final List<File> _trashFiles = [];
  final Map<String, DateTime> _trashDeleteTimes = {};

  late BannerAd _bannerAd;
  bool _isAdLoaded = false;

  final Map<String, Uint8List?> _videoThumbnails = {};

  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  int _currentThumbnailOps = 0;
  static const int _maxConcurrentThumbnails = 2;

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111', // Test Ad Unit ID
      size: AdSize.banner,
      request: AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (kDebugMode) {
            print('Ad failed to load: $error');
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final work = Directory(p.join(dir.path, 'flutter_camera_work'));
    if (!await work.exists()) return;

    final files = await work
        .list()
        .where((e) => e is File && _isMediaFile(e.path))
        .map((e) => e as File)
        .toList();

    // Batch processing for loading files
    const batchSize = 20;
    final allEntries = <Map<String, dynamic>>[];

    for (int i = 0; i < files.length; i += batchSize) {
      final batch = files.sublist(
        i,
        (i + batchSize < files.length) ? i + batchSize : files.length,
      );

      final entries = await Future.wait(
        batch.map((f) async {
          final lm = await f.lastModified();
          return {'file': f, 'time': lm};
        }),
      );

      allEntries.addAll(entries);
    }

    // Sort all entries after batch processing
    allEntries.sort(
      (a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime),
    );

    _flat = allEntries.map((e) => e['file'] as File).toList();
    _buildGroups();
    if (mounted) setState(() {});
  }

  // 💡 휴지통 기능 헬퍼 메서드들
  void _moveToTrash(File file) {
    _trashFiles.add(file);
    _trashDeleteTimes[file.path] = DateTime.now();
  }

  void _restoreFromTrash(File file) {
    _trashFiles.remove(file);
    _trashDeleteTimes.remove(file.path);
    _flat.add(file);
    _buildGroups();
  }

  void _permanentlyDeleteFromTrash(File file) {
    try {
      file.deleteSync();
      _trashFiles.remove(file);
      _trashDeleteTimes.remove(file.path);
    } catch (e) {
      debugPrint('Error permanently deleting file: $e');
    }
  }

  void _emptyTrash() {
    for (final file in _trashFiles) {
      try {
        file.deleteSync();
      } catch (e) {
        debugPrint('Error deleting file from trash: $e');
      }
    }
    _trashFiles.clear();
    _trashDeleteTimes.clear();
  }

  // 💡 휴지통 바텀시트 표시
  void _showTrashBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Column(
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Text(
                    '휴지통',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (_trashFiles.isNotEmpty)
                    TextButton.icon(
                      onPressed: () async {
                        final shouldEmpty = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('휴지통 비우기'),
                            content: const Text('휴지통의 모든 파일을 영구적으로 삭제하시겠습니까?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('취소'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('비우기'),
                              ),
                            ],
                          ),
                        );

                        if (shouldEmpty == true) {
                          _emptyTrash();
                          Navigator.of(context).pop(); // 바텀시트 닫기
                          if (mounted) setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('휴지통이 비워졌습니다'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      label: const Text(
                        '비우기',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            // 휴지통 파일 목록
            Expanded(
              child: _trashFiles.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 64,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 16),
                          Text(
                            '휴지통이 비어있습니다',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _trashFiles.length,
                      itemBuilder: (context, index) {
                        final file = _trashFiles[index];
                        final deleteTime = _trashDeleteTimes[file.path];
                        final timeAgo = deleteTime != null
                            ? _getTimeAgo(deleteTime)
                            : '';

                        return ListTile(
                          leading: Icon(
                            file.path.toLowerCase().endsWith('.mp4')
                                ? Icons.video_file
                                : Icons.image,
                            color: Colors.grey,
                          ),
                          title: Text(
                            p.basename(file.path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(timeAgo),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 복원 버튼
                              IconButton(
                                icon: const Icon(
                                  Icons.restore,
                                  color: Colors.blue,
                                ),
                                onPressed: () {
                                  _restoreFromTrash(file);
                                  Navigator.of(context).pop(); // 바텀시트 닫기
                                  if (mounted) setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${p.basename(file.path)} 복원되었습니다',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                                tooltip: '복원',
                              ),
                              // 영구 삭제 버튼
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_forever,
                                  color: Colors.red,
                                ),
                                onPressed: () async {
                                  final shouldDelete = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('영구 삭제'),
                                      content: Text(
                                        '${p.basename(file.path)} 파일을 영구적으로 삭제하시겠습니까?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(false),
                                          child: const Text('취소'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(true),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.red,
                                          ),
                                          child: const Text('삭제'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (shouldDelete == true) {
                                    _permanentlyDeleteFromTrash(file);
                                    if (mounted) setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '${p.basename(file.path)} 영구적으로 삭제되었습니다',
                                        ),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                tooltip: '영구 삭제',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // 💡 시간 차이 계산 헬퍼 메서드
  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  void _buildGroups() {
    _groupKeys.clear();
    _groupIndexMap.clear();
    final now = DateTime.now();
    for (var i = 0; i < _flat.length; i++) {
      final f = _flat[i];
      DateTime dt;
      try {
        dt = File(f.path).lastModifiedSync();
      } catch (_) {
        dt = now;
      }
      final key = _labelForDate(dt, now);
      _groupIndexMap.putIfAbsent(key, () => []).add(i);
    }
    _groupKeys.addAll(_groupIndexMap.keys);
  }

  String _labelForDate(DateTime dt, DateTime now) {
    final d = DateTime(dt.year, dt.month, dt.day);
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    if (d == today) return '오늘';
    if (d == yesterday) return '어제';
    if (d == tomorrow) return '내일';
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }

  static bool _isMediaFile(String path) {
    final e = p.extension(path).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.mp4', '.mov'].contains(e);
  }

  Future<Uint8List?> _generateThumbnail(String videoPath) async {
    if (_videoThumbnails.containsKey(videoPath)) {
      return _videoThumbnails[videoPath];
    }

    try {
      final thumbnail = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 128, // specify the height of the thumbnail
        quality: 75,
      );

      setState(() {
        _videoThumbnails[videoPath] = thumbnail;
      });

      return thumbnail;
    } catch (e) {
      print('Error generating thumbnail for $videoPath: $e');
      setState(() {
        _videoThumbnails[videoPath] = null;
      });
      return null;
    }
  }

  Future<Uint8List?> _generateThumbnailWithLimit(String videoPath) async {
    // Reuse existing Future if already in progress
    if (_thumbnailFutures.containsKey(videoPath)) {
      return await _thumbnailFutures[videoPath];
    }

    // Wait if max concurrent operations are reached
    while (_currentThumbnailOps >= _maxConcurrentThumbnails) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    _currentThumbnailOps++;
    try {
      final thumbnail = await _generateThumbnail(videoPath);
      _thumbnailFutures[videoPath] = Future.value(thumbnail);
      return thumbnail;
    } finally {
      _currentThumbnailOps--;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery'),
        actions: [
          // 💡 휴지통 아이콘 추가
          IconButton(
            icon: Badge(
              label: _trashFiles.isNotEmpty
                  ? Text('${_trashFiles.length}')
                  : null,
              child: const Icon(Icons.delete_outline),
            ),
            onPressed: _trashFiles.isEmpty
                ? null
                : () => _showTrashBottomSheet(context),
            tooltip: '휴지통',
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Groups: ${_groupKeys.length}  Media: ${_flat.length}  Keys: ${_groupKeys.take(4).join(', ')}',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          for (final key in _groupKeys) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Text(
                  key,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SliverGrid(
              delegate: SliverChildBuilderDelegate((context, idx) {
                final indices = _groupIndexMap[key] ?? [];
                final globalIndex = indices[idx];
                final file = _flat[globalIndex];
                final isVideo = file.path.toLowerCase().endsWith('.mp4');

                return GestureDetector(
                  onTap: () async {
                    try {
                      final deletedPath = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MediaViewer(
                            mediaFiles: _flat,
                            initialIndex: globalIndex,
                          ),
                        ),
                      );
                      if (deletedPath != null) {
                        // 삭제된 파일 목록에서 제거 후 갱신
                        _flat.removeWhere((f) => f.path == deletedPath);
                        _buildGroups();
                        if (mounted) setState(() {});
                      }
                    } catch (e) {
                      debugPrint('Error navigating to MediaViewer: $e');
                    }
                  },
                  onLongPress: () async {
                    // 휴지통 이동 확인 다이얼로그 표시
                    final shouldMoveToTrash = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('휴지통으로 이동'),
                        content: Text(
                          '${p.basename(file.path)} 파일을 휴지통으로 이동하시겠습니까?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('취소'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.orange,
                            ),
                            child: const Text('휴지통으로'),
                          ),
                        ],
                      ),
                    );

                    if (shouldMoveToTrash == true) {
                      // 파일을 휴지통으로 이동
                      _moveToTrash(file);
                      // 갤러리 목록에서 제거
                      _flat.removeWhere((f) => f.path == file.path);
                      _buildGroups();
                      if (mounted) setState(() {});

                      // 휴지통 이동 성공 메시지 표시
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${p.basename(file.path)} 휴지통으로 이동되었습니다',
                            ),
                            duration: const Duration(seconds: 2),
                            action: SnackBarAction(
                              label: '실행 취소',
                              onPressed: () {
                                // 실행 취소 시 휴지통에서 복원
                                _restoreFromTrash(file);
                                if (mounted) setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('휴지통 이동이 취소되었습니다'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: isVideo
                      ? FutureBuilder<Uint8List?>(
                          future: _generateThumbnailWithLimit(file.path),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            } else if (snapshot.hasError ||
                                snapshot.data == null) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  Image.file(file, fit: BoxFit.cover),
                                  const Icon(
                                    Icons.play_circle_outline,
                                    color: Colors.white,
                                  ),
                                ],
                              );
                            } else {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Image.file(
                                        file,
                                        fit: BoxFit.cover,
                                      );
                                    },
                                  ),
                                  const Icon(
                                    Icons.play_circle_outline,
                                    color: Colors.white,
                                  ),
                                ],
                              );
                            }
                          },
                        )
                      : Image.file(file, fit: BoxFit.cover),
                );
              }, childCount: _groupIndexMap[key]?.length ?? 0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _isAdLoaded
          ? SizedBox(
              height: _bannerAd.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd),
            )
          : null,
    );
  }
}
