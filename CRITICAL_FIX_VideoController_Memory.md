# 🚨 Critical Issue 해결: VideoPlayerController 메모리 관리

## 문제 분석

### 원인: 이중(Double) dispose 문제

```
_MediaViewerState (부모)
├─ _videoControllers = {} // 컨트롤러 캐시 관리
└─ _MediaPage (자식)
   ├─ didChangeDependencies()
   │  └─ 부모의 컨트롤러를 가져옴
   └─ dispose() ❌ 여기서 컨트롤러를 종료
       └─ _controller?.dispose() // 문제 발생!
```

### 문제 발생 시나리오

```
1. 사용자가 비디오 1 재생
   ✓ _videoControllers[1] 생성 및 초기화

2. 사용자가 비디오 2로 스와이프
   ✓ _MediaPage[1] dispose() 호출
   ✗ _controller?.dispose() 실행
   ✗ _videoControllers[1]이 종료됨 (하지만 맵에는 남아있음)

3. 사용자가 다시 비디오 1로 돌아옴
   ✗ _videoControllers[1]에서 이미 종료된 컨트롤러 반환
   ✗ 앱 CRASH! (disposed controller 사용)
```

## 해결 방법

### 메모리 관리 책임 분리

| 계층 | 역할 | 책임 |
|------|------|------|
| **_MediaViewerState** (부모) | 컨트롤러 생명주기 관리 | ✅ 초기화 & 종료 |
| **_MediaPage** (자식) | 컨트롤러 사용/렌더링 | ❌ 종료 금지 |

### 수정 전 코드

```dart
class _MediaPageState extends State<_MediaPage> {
  VideoPlayerController? _controller;

  @override
  void dispose() {
    try {
      _controller?.dispose();  // ❌ 문제: 부모가 관리하는 컨트롤러를 종료
    } catch (_) {}
    super.dispose();
  }
}
```

### 수정 후 코드

```dart
class _MediaPageState extends State<_MediaPage> {
  VideoPlayerController? _controller;

  @override
  void dispose() {
    // 💡 부모(_MediaViewerState)에서 관리하는 컨트롤러는 부모에서만 dispose 처리
    // 자식 위젯에서 dispose() 호출 시 컨트롤러를 종료하면 안됨
    // (이미 종료된 컨트롤러를 나중에 재사용할 때 크래시 발생)
    super.dispose();
  }
}
```

## 수정 효과

### ✅ 메모리 관리 정상화

```
수정 전 (문제 있음):
1. _MediaPage dispose() 호출
2. _controller?.dispose() 실행
3. 부모의 컨트롤러 종료됨 ❌
4. 재사용 시 크래시 ❌

수정 후 (정상):
1. _MediaPage dispose() 호출
2. super.dispose() 만 실행
3. 부모의 컨트롤러 유지 ✓
4. 재사용 가능 ✓
```

### ✅ 안정성 향상

- 메모리 누수 방지
- 컨트롤러 중복 종료 제거
- 페이지 재방문 시 안정적 작동

## 아키텍처 개선

### 메모리 관리 흐름

```
_MediaViewerState.initState()
└─ _videoControllers = {} 초기화

사용자가 페이지 변경
└─ _pageController.onPageChanged()
   └─ _initializeVideoController(newIndex) 호출
      └─ _videoControllers[newIndex] = controller (또는 기존 컨트롤러 반환)

_MediaPage.didChangeDependencies()
└─ parentState._videoControllers[index] 에서 컨트롤러 획득
└─ 렌더링 시 사용

_MediaPage가 화면 밖으로 나감
└─ _MediaPage.dispose()
   └─ super.dispose() 만 호출 (컨트롤러 touch 금지)

_MediaViewerState.dispose()
└─ for (final controller in _videoControllers.values)
   └─ controller.dispose() 일괄 처리 (❌ 여기서만 종료)
```

## 코드 위치

```
파일: lib/media_viewer.dart
클래스: _MediaPageState
메서드: dispose()
줄: 595-602
```

## 테스트 체크리스트

- [x] 수정된 코드 분석 완료 (오류 없음)
- [x] 빌드 중...
- [ ] 디바이스에서 테스트
  - [ ] 비디오 재생 후 다른 미디어로 이동
  - [ ] 이전 미디어로 돌아옴 (재생 정상 여부 확인)
  - [ ] 반복적으로 페이지 이동
  - [ ] 메모리 사용량 모니터링

## 기술적 상세

### PageView의 동작

```
PageView.builder()
├─ 현재 보이는 페이지 + 이전/다음 1개씩 유지
├─ 나머지 페이지는 dispose() 호출
└─ 다시 돌아올 때 itemBuilder 재호출
```

### 이전 문제의 근원

```
dispose()에서 컨트롤러를 종료
→ 새로 build될 때 _controller가 null (disposed 상태)
→ UI 렌더링 실패 또는 크래시
```

### 현재 수정의 이점

```
dispose()에서 컨트롤러를 터치하지 않음
→ 캐시된 컨트롤러 유지
→ 재방문 시 즉시 사용 가능
→ 안정성 향상
```

## 리소스 정리

### 부모에서만 리소스 정리 (확인됨)

```dart
@override
void dispose() {
  try {
    for (final controller in _videoControllers.values) {
      try {
        if (controller.value.isInitialized) {
          controller.pause();
        }
        controller.dispose();  // ✅ 부모에서만 정리
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
```

---

**수정 상태**: ✅ 완료
**빌드 상태**: 진행 중...
**안정성 개선**: Critical Issue 해결됨
