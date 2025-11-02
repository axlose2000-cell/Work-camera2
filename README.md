# work_camera_gallery

업무용 사진/갤러리 분리 Flutter 앱

## 주요 진행상황

- 업무 사진은 앱 내에서만 관리, 기본 갤러리에는 노출되지 않음

## 어제 / 오늘 작업 요약

- 어제:
  - `lib/media_viewer.dart` 내부 비디오 초기화 로직 점검 및 개선 (on-demand 초기화, 자동 재시도 제거)
  - `lib/camera_screen.dart`의 타이머/라이프사이클 관련 setState 안전성 수정
  - 디바이스에서 재현 테스트를 통해 VideoPlayer.initialize() 타임아웃과 관련 로그 수집

- 오늘:
  - 비디오 초기화 동시성 제어 추가 (동시 초기화 제한), 실패 시 부분적인 컨트롤러 dispose 및 사용자 재시도 UI 추가
  - 썸네일 생성/디스크 캐시 구현 및 중복 생성 방지 로직 추가
  - `lib/gallery_screen.dart`를 날짜(월/일)별로 그룹화하고, 섹션 헤더(Sticky) 및 '오늘/어제' 상대 날짜 레이블 추가
  - Sliver 기반 레이아웃으로 섹션 헤더 고정(sticky header) 구현 및 관련 렌더 예외를 수정

## 해결된 문제

1. 비디오 초기화 동시성 제어 완료.
2. 썸네일 생성 및 디스크 캐시 로직 완료.
3. 갤러리 날짜별 그룹화 및 섹션 헤더 고정 완료.
4. Sliver 기반 레이아웃 렌더 예외 수정 완료.

## 남은 작업

1. 네이티브 크래시(SIGSEGV, Vulkan 드라이버) 원인 분석
	- 전체 `adb logcat`과 tombstone 파일 수집 및 분석 필요
	- 소프트웨어 렌더링으로 실행해 드라이버/백엔드 문제 여부를 분리 테스트
2. `media_viewer.dart` 추가 방어 적용
	- 화면에서 벗어난 페이지의 VideoPlayerController 즉시 dispose
	- 부모 수준의 엄격한 초기화 큐(싱글 인스턴스) 적용 및 백오프 정책 도입
3. 성능/UX 개선
	- Sliver 성능 개선(대량 이미지에서의 스크롤 최적화), 이미지 페이징 또는 썸네일 캐시 정책 개선
	- '오늘/어제' 라벨을 지역화(Intl)하고 sticky header 스타일 다듬기

## GitHub 반영

변경사항을 로컬 저장소에 커밋했습니다. 원격(GitHub)에 푸시하시려면 아래 명령을 사용하세요:

```powershell
# 로컬 커밋 후 원격 푸시(예: origin/master)
git add README.md
git commit -m "docs: update README with yesterday/today summary and next steps"
git push origin master
```

원하시면 제가 이 저장소에 대해 로컬 커밋을 만들고(이미 수행), 원격으로 푸시까지 진행해 드릴 수 있습니다. 이 경우 원격 접근 권한(credential)이 필요합니다.

---

## 중요 이슈: 섬네일 로딩 후 무한 스피닝

- 현상: 최근에 썸네일에 로딩 플레이스홀더(Shimmer)를 추가한 이후로 일부 비디오가 뷰어에서 '무한 로딩(spinning)' 상태에 빠지는 문제가 재현되었습니다. 이 문제는 오늘 디버깅으로도 완전히 해결되지 않았고, 추가 분석이 필요합니다.
- 원인 추정(우선 가설): 썸네일 생성/렌더링과 VideoPlayer 초기화 간의 타이밍/경합, 또는 SurfaceTexture 할당 타이밍이 꼬이면서 VideoPlayer.initialize()가 완료되지 않거나 타임아웃되는 케이스.
- 조치 계획 (내일 우선 처리):
  1. 섬네일 placeholder를 임시로 비활성화하여 문제가 섬네일 쪽인지 확인
  2. VideoPlayer 초기화 흐름을 부모(또는 중앙)에서 시리얼화(한 번에 한 파일만 initialize)하여 리소스 경합 완화
  3. 초기화 실패 시 명확한 상태(에러 UI) 노출 및 재시도 로직 보강
  4. adb logcat과 네이티브 tombstone(크래시 덤프) 확보 및 분석

이 이슈는 내일 최우선으로 이어서 조사/해결할 예정입니다.
- 썸네일/갤러리 이미지를 누르면 슬라이드 뷰어로 전체 업무 사진 탐색 가능

## 현재 문제점 및 개선 필요사항
- 이미지 뷰어 더블탭 확대 UX: 한 번에 원하는 배율로 확대되지 않는 경우가 있음 (커스텀 확대/축소 로직 적용 중)
- 미디어스토어 동기화: 일부 기기에서 파일 탐색/삭제 시 동기화 지연 가능성
- 사진 저장/불러오기 성능: 이미지가 많아질 경우 로딩 속도 저하 가능성
- iOS/웹 호환성 미검증 (현재 Android 중심 개발)
- 기타 UI/UX 세부 개선 및 테스트 필요

---
진행상황 및 기능 문의는 깃허브 이슈로 남겨주세요.

## 최신 진행상황 업데이트 (2025년 11월 2일)

### 최근 완료 작업

- `lib/media_viewer.dart`: 비디오 초기화 타임아웃을 30초로 연장하고 동적 조정 가능성을 위한 플레이스홀더 추가.
- `lib/camera_screen.dart`: `_lastPreviewBytes`를 `dispose()`에서 명시적으로 해제하여 메모리 누수 방지.
- `lib/gallery_screen.dart`: 대규모 갤러리 스크롤을 위한 페이지네이션 추가.
- `lib/image_viewer.dart`: 미사용 파일로 확인되어 제거 완료.
- `pubspec.yaml`: `device_info_plus` 의존성 추가로 동적 동시성 제어 구현.

### 다음 작업 예정

- 디바이스에서 앱 실행 후 검증:
  - 썸네일 표시, 비디오 초기화, 광고 로드 동작 확인.
  - 로그 수집 및 분석.
- iOS Info.plist 설정 확인:
  - AdMob/ATS 항목을 최소 권한으로 적용.
- AdMob 실배너 ID 적용:
  - 프로덕션 광고 유닛 ID로 교체 및 동작 확인.

## ⚠️ 주요 이슈 및 개선 사항 (2025년 11월 2일)

### 1. 비디오 초기화 타임아웃 문제
- **현재**: `media_viewer.dart`에서 15초 타임아웃이 보수적.
  ```dart
  await _controller!.initialize().timeout(const Duration(seconds: 15));
  ```
- **권장사항**:
  - 타임아웃을 더 길게 (20-30초).
  - 기기 사양에 따라 동적 조정.
  - 초기화 전 메모리 상태 체크.

### 2. 메모리 누수 위험
- **현재**: `camera_screen.dart`의 `_lastPreviewBytes`가 계속 유지될 수 있음.
  ```dart
  Uint8List? _lastPreviewBytes;
  ```
- **개선안**:
  ```dart
  @override
  void dispose() {
    _lastPreviewBytes = null;  // 명시적 해제
    _flashTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }
  ```

### 3. ImageViewer.dart 미사용
- **현재**: `ImageViewer.dart`가 실제로 사용되지 않음. 대신 `MediaViewer`를 사용 중.
- **제안**: 불필요한 파일 제거 또는 통합.

### 4. 에러 처리 부족
- **현재**: 여러 곳에서 `try-catch` 후 단순히 `debugPrint`만 실행.
  ```dart
  catch (e) {
    debugPrint('permission request error: $e');
    return false;
  }
  ```
- **개선안**:
  ```dart
  catch (e) {
    debugPrint('permission request error: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('권한 오류: $e'))
      );
    }
    return false;
  }
  ```

### 5. 동시성 제어 강화 필요
- **현재**: `_maxConcurrentInits = 1`로 고정.
- **문제**: 기기 사양을 고려하지 않음.
- **개선안**:
  ```dart
  int get _maxConcurrentInits {
    final info = await DeviceInfoPlugin().deviceInfo;
    return (info.totalMemory ?? 4000000000) > 3000000000 ? 2 : 1;
  }
  ```

### 6. AdMob 테스트 ID 사용
- **현재**: `gallery_screen.dart` & `media_viewer.dart`에서 테스트 ID 사용.
  ```dart
  adUnitId: 'ca-app-pub-3940256099942544/9214589741',  // 테스트 ID
  ```
- **주의**: 프로덕션 배포 전 실제 AdMob ID로 변경 필요.

### 7. 권한 요청 UX 개선
- **현재**: 비디오 녹화 중 마이크 권한 재요청.
  ```dart
  if (_captureMode == CaptureMode.video) {
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      // 미리 앱 시작 시 요청하는 게 나음
    }
  }
  ```
- **제안**: `initState`에서 사전 권한 요청.

### 8. 파일 시스템 경로 최적화
- **현재**: 반복되는 경로 생성.
  ```dart
  final Directory appDir = await getApplicationDocumentsDirectory();
  final Directory workDir = Directory('${appDir.path}/flutter_camera_work');
  ```
- **개선안**:
  ```dart
  const String WORK_DIR_NAME = 'flutter_camera_work';

  Future<Directory> getWorkDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final workDir = Directory('${appDir.path}/$WORK_DIR_NAME');
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    return workDir;
  }
  ```

### 9. 비디오 녹화 상태 관리
- **현재**: 녹화 중 앱 백그라운드 전환 시 처리 필요.
  ```dart
  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    // 앱이 일시 중지되면?
  }
  ```
- **제안**: 앱 라이프사이클 리스너 추가.
  ```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isRecording) {
      _stopRecording();
    }
  }
  ```

### 10. 성능: 큰 갤러리 스크롤
- **현재**: 모든 파일을 한 번에 로드.
  ```dart
  final files = await workDir.list().where(...).toList();
  ```
- **개선안**: 페이지네이션 또는 가상 스크롤.
  ```dart
  ListView.builder(
    itemCount: _groupKeys.length,
    itemBuilder: (context, gi) {
      return _buildGroupLazy(_groupKeys[gi]);
    }
  )
  ```

## 2025년 11월 3일 진행 상황

- **광고 통합**:
  - `google_mobile_ads` 패키지를 사용하여 배너 광고를 `media_viewer.dart`와 `gallery_screen.dart`에 통합.
  - 광고가 콘텐츠를 가리지 않도록 `bottomNavigationBar`에 배치.

- **버그 수정**:
  - `gallery_screen.dart`에서 누락된 닫는 괄호 `)` 문제 해결.
  - `flutter pub upgrade`를 통해 종속성 일부를 최신 버전으로 업데이트.

- **빌드 성공**:
  - 수정된 코드로 빌드 성공 (`app-release.apk` 생성).

## 다음 작업

1. 광고가 모든 디바이스에서 올바르게 표시되는지 테스트.
2. 추가적인 UI/UX 개선 작업.
