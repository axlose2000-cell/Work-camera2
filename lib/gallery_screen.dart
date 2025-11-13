// Minimal gallery screen
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'media_viewer.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:mutex/mutex.dart';

// getWorkDirectory, getTrashDirectory 직접 정의 (임시)
const String workDirName = 'flutter_camera_work';
const String trashDirName = 'trash';
const String trashAlbumName = 'WorkCamera_Trash';
Future<Directory> getWorkDirectory() async {
  final appDir = await getApplicationDocumentsDirectory();
  final workDir = Directory('${appDir.path}/$workDirName');
  if (!await workDir.exists()) {
    await workDir.create(recursive: true);
  }
  return workDir;
}

Future<Directory> getTrashDirectory() async {
  final workDir = await getWorkDirectory();
  final trashDir = Directory('${workDir.path}/$trashDirName');
  if (!await trashDir.exists()) {
    await trashDir.create(recursive: true);
  }
  return trashDir;
}

// [광고 ID 및 상수] ---------------------------------------------
const String bannerAdUnitId =
    'ca-app-pub-3940256099942544/6300978111'; // 하단 배너 (기존)
const String interstitialAdUnitId =
    'ca-app-pub-3940256099942544/1033173712'; // 테스트 ID
const String nativeAdUnitId =
    'ca-app-pub-3940256099942544/2247696110'; // 네이티브 광고 테스트 ID (인라인용)
// 💡 광고를 삽입할 그룹(날짜) 간격 설정
const int adGroupInterval = 2; // 2개의 그룹(날짜)마다 광고 삽입
const int adShowFrequency = 10; // 갤러리 종료 10회당 1회 광고 표시
// -------------------------------------------------------------

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with WidgetsBindingObserver {
  // ✅ AssetEntity 기반 변수 추가 및 수정
  List<AssetEntity> _assetList = []; // 전체 Asset 목록
  final List<String> _groupKeys = []; // 날짜 그룹 키
  final Map<String, List<int>> _groupIndexMap =
      {}; // 그룹 키 -> _assetList의 인덱스 리스트

  late BannerAd _bannerAd;
  bool _isAdLoaded = false;

  InterstitialAd? _interstitialAd;
  int _adCounter = 0;
  DateTime? _lastQuitAttempt;
  static const Duration _quitTimeout = Duration(seconds: 2);

  // 다중 선택 상태 관리
  bool _isMultiSelectMode = false;
  final Set<int> _selectedIndexes = {};

  // 휴지통 모드 상태 관리
  bool _isTrashMode = false;
  final List<AssetEntity> _trashList = []; // 휴지통에 있는 파일 목록

  // 사진 및 비디오 개수 상태 변수 추가
  int _photoCount = 0;
  int _videoCount = 0;

  // 💡 인라인 네이티브 광고 관련 변수 추가
  NativeAd? _nativeAd;
  bool _isNativeAdLoaded = false;

  // [앱 평가 유도 로직 상수/키 수정]
  static const String _kFirstLaunchDate = 'rating_first_launch_date';
  static const String _kRatedOrPermanentlyDismissed =
      'rating_permanently_dismissed';
  static const String _kLastPromptDate = 'rating_last_prompt_date';

  final _prefsMutex = Mutex();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAllFiles();
    _bannerAd = BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          setState(() {
            _isAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _handleAdError(error);
        },
      ),
    )..load();

    _loadAdCounter().then((_) {
      _loadInterstitialAd();
    });

    _loadNativeAd(); // 💡 네이티브 광고 로드 함수 호출

    // 💡 [앱 평가 유도 로직 호출]
    _checkAndShowRatingPrompt();
  }

  // 💡 Native Ad 로드 함수 추가
  void _loadNativeAd() {
    _nativeAd = NativeAd(
      adUnitId: nativeAdUnitId,
      factoryId: 'listTileAd', // Custom Native Ad 형식에 맞춰 정의된 템플릿 ID를 사용해야 합니다.
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          setState(() {
            _isNativeAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Native Ad failed to load: $error');
        },
      ),
    );
    _nativeAd!.load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
                onAdDismissedFullScreenContent: (InterstitialAd ad) {
                  ad.dispose();
                  _loadInterstitialAd();
                },
                onAdFailedToShowFullScreenContent:
                    (InterstitialAd ad, AdError error) {
                      ad.dispose();
                      _loadInterstitialAd();
                    },
              );
        },
        onAdFailedToLoad: (LoadAdError error) {
          if (kDebugMode) {
            print('Interstitial ad failed to load: $error');
          }
        },
      ),
    );
  }

  Future<void> _loadAdCounter() async {
    await _prefsMutex.protect(() async {
      final prefs = await SharedPreferences.getInstance();
      _adCounter = prefs.getInt('adCounter') ?? 0;
    });
  }

  Future<void> _saveAdCounter() async {
    await _prefsMutex.protect(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('adCounter', _adCounter);
    });
  }

  Future<bool> _onWillPop() async {
    if (_lastQuitAttempt == null ||
        DateTime.now().difference(_lastQuitAttempt!) > _quitTimeout) {
      _lastQuitAttempt = DateTime.now();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('한번 더 누르면 갤러리가 종료됩니다.'),
            duration: _quitTimeout,
          ),
        );
      }
      return false;
    }

    _adCounter++;
    await _saveAdCounter();

    if (_adCounter >= adShowFrequency) {
      if (_interstitialAd != null) {
        _interstitialAd!.show();
        _adCounter = 0;
        await _saveAdCounter();
      }
    }

    return true;
  }

  Future<void> _loadAllFiles() async {
    // 1. 권한 확인
    final ps = await PhotoManager.requestPermissionExtend();
    if (ps.isAuth != true) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('갤러리 접근 권한이 필요합니다.')));
      }
      return;
    }

    // 2. 앨범 찾기 ("flutter_camera_work")
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image | RequestType.video,
      // onlyAccessAlbums: true,
      // pathList: [workDirName],
      filterOption: FilterOptionGroup(
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );

    AssetPathEntity? workAlbum;
    for (var album in albums) {
      if (album.name == workDirName) {
        workAlbum = album;
        break;
      }
    }

    if (workAlbum == null) {
      if (mounted) {
        setState(() {
          _assetList.clear();
          _groupKeys.clear();
          _groupIndexMap.clear();
        });
      }
      return;
    }

    // 3. Asset 로드 (모든 페이지)
    // 페이지네이션 적용
    // 페이지네이션 최적화: 병렬 처리 및 메모리 관리
    const int pageSize = 100;
    final int totalAssets = await workAlbum.assetCountAsync;

    // 병렬 처리 제한 및 에러 처리 추가
    const int maxConcurrent = 3; // 리소스 절약
    final List<AssetEntity> assets = [];
    final futures = <Future<List<AssetEntity>>>[];

    try {
      for (int page = 0; page * pageSize < totalAssets; page++) {
        if (futures.length >= maxConcurrent) {
          final completed = await Future.wait(futures);
          for (final pageAssets in completed) {
            assets.addAll(pageAssets);
          }
          futures.clear();
        }
        futures.add(workAlbum.getAssetListPaged(page: page, size: pageSize));
      }

      if (futures.isNotEmpty) {
        final results = await Future.wait(futures);
        for (final pageAssets in results) {
          assets.addAll(pageAssets);
        }
      }
    } catch (e) {
      debugPrint('파일 로드 중 오류: $e');
    }

    // 4. 날짜별 그룹화
    _assetList.clear();
    _groupKeys.clear();
    _groupIndexMap.clear();

    // 사진 및 비디오 개수 계산
    int photoCount = 0;
    int videoCount = 0;
    for (final asset in assets) {
      if (asset.type == AssetType.image) {
        photoCount++;
      } else if (asset.type == AssetType.video) {
        videoCount++;
      }
    }

    setState(() {
      _assetList = assets;
      _photoCount = photoCount;
      _videoCount = videoCount;
    });
  }

  // Add loading indicator
  Widget _buildLoadingIndicator() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildGalleryContent() {
    final List<Widget> slivers = [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            '사진: $_photoCount, 비디오: $_videoCount',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    ];

    // 💡 인라인 광고 삽입 로직
    int groupCount = 0;
    for (final key in _groupKeys) {
      // 1. 날짜 헤더 (SliverToBoxAdapter)
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              key,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );

      // 2. 해당 그룹의 그리드 (SliverGrid)
      slivers.add(
        SliverGrid(
          delegate: SliverChildBuilderDelegate((context, idx) {
            final indices = _groupIndexMap[key] ?? [];
            final globalIndex = indices[idx];
            return _buildGridItem(context, globalIndex);
          }, childCount: _groupIndexMap[key]?.length ?? 0),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
        ),
      );

      groupCount++;

      // 3. 광고 삽입 조건: 정해진 그룹 간격(adGroupInterval)마다 네이티브 광고 삽입
      if (_isNativeAdLoaded && groupCount % adGroupInterval == 0) {
        slivers.add(
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              height: 120, // 인라인 광고가 들어갈 높이 설정
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey[100], // 배경색으로 광고 영역을 명확히 구분
                border: Border.all(color: Colors.grey[300]!),
              ),
              // 네이티브 광고 위젯
              child: AdWidget(ad: _nativeAd!),
            ),
          ),
        );
      }
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isMultiSelectMode
              ? Text('${_selectedIndexes.length}개 선택됨')
              : Text(_isTrashMode ? '휴지통' : '갤러리'),
          actions: _isMultiSelectMode
              ? [
                  IconButton(
                    icon: const Icon(Icons.restore),
                    onPressed: _restoreSelectedFromTrash,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: _deleteSelectedFromTrash,
                  ),
                ]
              : [
                  IconButton(
                    icon: Icon(_isTrashMode ? Icons.arrow_back : Icons.delete),
                    onPressed: _toggleTrashMode,
                  ),
                ],
        ),
        body: FutureBuilder(
          future: _loadAllFiles(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingIndicator();
            }
            return CustomScrollView(
              slivers: slivers, // 💡 완성된 slivers 리스트 사용
            );
          },
        ),
        bottomNavigationBar: _isAdLoaded
            ? SizedBox(
                height: _bannerAd.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd),
              )
            : null,
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, int globalIndex) {
    final asset = _assetList[globalIndex];

    return GestureDetector(
      onLongPress: () => _showContextMenu(context, asset),
      onTap: () => _openMediaViewer(globalIndex),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // AssetEntityImageProvider를 사용하여 이미지를 로드합니다.
          // photo_manager_image_provider 패키지가 설치되었으므로, 이를 활용하여 문제를 해결합니다.
          Image(
            image: AssetEntityImageProvider(asset, isOriginal: false),
            fit: BoxFit.cover,
          ),
          if (asset.type == AssetType.video)
            const Center(
              child: Icon(
                Icons.play_circle_outline,
                color: Colors.white,
                size: 36,
              ),
            ),
        ],
      ),
    );
  }

  void _openMediaViewer(int initialIndex) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MediaViewer(mediaAssets: _assetList, initialIndex: initialIndex),
      ),
    );

    _loadAllFiles();
  }

  // 💡 AssetEntity 기반 삭제 함수 (시스템 휴지통 사용)
  Future<void> _deleteAsset(AssetEntity asset) async {
    // 1. PhotoManager를 사용하여 Asset 삭제 요청
    // Android Q+ 및 iOS에서는 시스템 휴지통으로 이동합니다.
    final List<String> deletedIds = await PhotoManager.editor.deleteWithIds(
      [asset.id],
      // 💡 참고: skipPermissionRequest: true는 미리 권한을 받았다고 가정합니다.
    );

    if (deletedIds.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${deletedIds.length}개의 파일이 시스템 휴지통으로 이동되었습니다.'),
            // 💡 복구는 시스템 갤러리 앱에서 하도록 안내
            action: SnackBarAction(
              label: '안내',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('복구 및 완전 삭제는 시스템 갤러리 앱의 휴지통에서 진행해주세요.'),
                  ),
                );
              },
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파일 삭제에 실패했습니다. 권한을 확인해주세요.')),
        );
      }
    }

    // 갤러리 새로고침
    _loadAllFiles();
  }

  // 💡 AssetEntity 기반 컨텍스트 메뉴
  void _showContextMenu(BuildContext context, AssetEntity asset) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // 💡 삭제 메뉴: 휴지통으로 이동
              ListTile(
                leading: const Icon(Icons.delete_sweep, color: Colors.red),
                title: const Text('휴지통으로 이동'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteAsset(asset); // 👈 AssetEntity 전달
                },
              ),
              // TODO: 추후 공유, 편집 등 추가 가능
            ],
          ),
        );
      },
    );
  }

  void _toggleTrashMode() {
    setState(() {
      _isTrashMode = !_isTrashMode;
      _isMultiSelectMode = false;
      _selectedIndexes.clear();
    });
  }

  void _deleteSelectedFromTrash() async {
    setState(() {
      _selectedIndexes.toList().sort((a, b) => b.compareTo(a));
      for (var index in _selectedIndexes) {
        _trashList.removeAt(index);
      }
      _selectedIndexes.clear();
      _isMultiSelectMode = false;
    });
    // TODO: 실제 파일 삭제 로직 추가
  }

  void _restoreSelectedFromTrash() async {
    setState(() {
      _selectedIndexes.toList().sort((a, b) => b.compareTo(a));
      for (var index in _selectedIndexes) {
        final asset = _trashList.removeAt(index);
        _assetList.add(asset);
      }
      _selectedIndexes.clear();
      _isMultiSelectMode = false;
    });
    // TODO: 실제 파일 복구 로직 추가
  }

  // [async 누락 수정]
  Future<void> _checkAndShowRatingPrompt() async {
    await _prefsMutex.protect(() async {
      final prefs = await SharedPreferences.getInstance();

      // 1. 영구 종료되었는지 확인 (평가했거나 3회 거절)
      final bool permanentlyDismissed =
          prefs.getBool(_kRatedOrPermanentlyDismissed) ?? false;
      if (permanentlyDismissed) {
        return;
      }

      // 2. 첫 실행 날짜 기록
      int firstLaunchTimestamp = prefs.getInt(_kFirstLaunchDate) ?? 0;
      if (firstLaunchTimestamp == 0) {
        // 첫 실행 날짜 기록 후 종료 (다음 실행부터 카운트)
        await prefs.setInt(
          _kFirstLaunchDate,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    });
  }

  @override
  void dispose() {
    _bannerAd.dispose();
    _nativeAd?.dispose(); // 💡 네이티브 광고 해제
    super.dispose();
  }

  // _handleAdError 메서드 재정의
  void _handleAdError(AdError error) {
    if (kDebugMode) {
      print('Ad failed to load: ${error.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('갤러리'),
        actions: [
          IconButton(
            icon: Icon(_isTrashMode ? Icons.restore : Icons.delete_outline),
            onPressed: () {
              setState(() {
                _isTrashMode = !_isTrashMode;
              });
              _loadAllFiles();
            },
          ),
        ],
      ),
      body: _isTrashMode ? _buildTrashModeUI() : _buildGalleryContent(),
      bottomNavigationBar: _isAdLoaded
          ? SizedBox(height: 60, child: AdWidget(ad: _bannerAd))
          : null,
    );
  }

  Widget _buildTrashModeUI() {
    return _trashList.isEmpty
        ? const Center(child: Text('휴지통이 비어있습니다'))
        : GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: _trashList.length,
            itemBuilder: (context, index) {
              final asset = _trashList[index];
              final isSelected = _selectedIndexes.contains(index);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedIndexes.remove(index);
                    } else {
                      _selectedIndexes.add(index);
                    }
                  });
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FutureBuilder<File?>(
                      future: asset.file,
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return Image.file(snapshot.data!, fit: BoxFit.cover);
                        }
                        return Container(color: Colors.grey[400]);
                      },
                    ),
                    if (isSelected)
                      Container(
                        color: Colors.blue.withValues(alpha: 0.5),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                  ],
                ),
              );
            },
          );
  }
}
