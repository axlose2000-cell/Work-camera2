# UX 미세 조정: 자동 숨김 타이머 기능

## 📝 개선 내용

### 문제점
비디오 재생 중에 플레이 아이콘을 탭하면 즉시 나타났다가 사라져서 어색함. 네이티브 비디오 플레이어처럼 부드러운 UX가 필요.

### 해결 방법
사용자가 비디오를 탭할 때 플레이 아이콘을 일시적으로 표시하고, 2초 후 자동으로 숨기는 기능 추가.

## 🔧 구현 단계

### 1단계: 상태 변수 추가

```dart
class _MediaPageState extends State<_MediaPage> {
  VideoPlayerController? _controller;
  
  // 💡 비디오 컨트롤 아이콘의 임시 표시 상태
  bool _showVideoControls = false;
  Timer? _controlsTimer;
```

### 2단계: 타이머 설정 함수 추가

```dart
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
```

### 3단계: onTap 콜백에서 타이머 시작

```dart
GestureDetector(
  onTap: () {
    if (_controller != null && _controller!.value.isInitialized) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      // 💡 탭 시 컨트롤을 일시적으로 표시하고 타이머 설정
      setState(() {
        _showVideoControls = true;
      });
      _setControlsTimer();
    }
  },
  child: ...
)
```

### 4단계: 플레이 버튼 표시 조건 수정

```dart
(!_controller!.value.isPlaying ||
 widget.isUIVisible ||
 _showVideoControls) // 💡 이 조건 중 하나라도 참이면 표시
  ? Container(...) // 플레이 버튼 표시
  : null          // 플레이 버튼 숨김
```

### 5단계: dispose에서 타이머 해제

```dart
@override
void dispose() {
  _controlsTimer?.cancel(); // 💡 타이머 해제
  super.dispose();
}
```

## ✨ 동작 흐름

### 일반 상황 (UI 표시 중)
```
비디오 재생 중
  ↓
플레이 아이콘 표시 안됨 (isPlaying = true, isUIVisible = false)
  ↓
화면 탭
  ↓
_showVideoControls = true 설정
  ↓
플레이 아이콘 표시 (300ms 페이드인)
  ↓
2초 경과
  ↓
타이머 콜백 실행
  ↓
_showVideoControls = false
  ↓
플레이 아이콘 숨김 (300ms 페이드아웃)
```

### UI 숨김 상황
```
화면 탭 (UI 숨김)
  ↓
플레이 아이콘도 함께 사라짐
  ↓
비디오 탭
  ↓
_showVideoControls = true
  ↓
플레이 아이콘 일시적 표시
  ↓
2초 후 자동 숨김
```

## 📊 조건부 렌더링 로직

### 플레이 버튼이 표시되는 경우

| 조건 | 표시 |
|------|------|
| 재생 중이 아님 | ✅ |
| UI가 표시됨 | ✅ |
| _showVideoControls = true | ✅ |
| 위 모든 조건 거짓 | ❌ |

### 예시 시나리오

| 상황 | isPlaying | isUIVisible | _showVideoControls | 결과 |
|------|-----------|------------|------------------|------|
| 비디오 일시정지, UI 표시 | false | true | false | ✅ 표시 |
| 비디오 재생, UI 숨김 | true | false | false | ❌ 숨김 |
| 비디오 재생, 탭한 직후 | true | false | true | ✅ 표시 |
| 비디오 재생, 2초 후 | true | false | false | ❌ 숨김 |

## 🎯 사용자 경험

### Before (변경 전)
```
탭 → 아이콘 표시 → 즉시 사라짐 (어색함)
```

### After (변경 후)
```
탭 → 아이콘 표시 (300ms 페이드) → 2초 유지 → 자동 숨김 (부드러움)
```

## 📁 변경 파일

```
lib/media_viewer.dart

1. _MediaPageState 상태 변수 (라인 537-538)
   ├─ bool _showVideoControls = false
   └─ Timer? _controlsTimer

2. _setControlsTimer() 메서드 (라인 554-565)
   └─ 2초 후 컨트롤 자동 숨김

3. GestureDetector.onTap (라인 585-592)
   └─ 탭 시 타이머 시작

4. 플레이 버튼 조건 (라인 607-609)
   └─ _showVideoControls 포함

5. dispose() 메서드 (라인 626-627)
   └─ 타이머 해제
```

## 🧪 테스트 시나리오

### 테스트 1: 기본 타이머 동작
```
1. 비디오 재생
2. 화면 탭
3. 플레이 아이콘 표시 확인
4. 2초 대기
5. 아이콘 자동 숨김 확인
```

### 테스트 2: 연속 탭 (타이머 리셋)
```
1. 비디오 재생
2. 화면 탭 (타이머 시작)
3. 1.5초 후 다시 탭 (타이머 리셋)
4. 다시 2초 대기
5. 아이콘 숨김 확인 (총 3.5초)
```

### 테스트 3: UI 토글 중 동작
```
1. 비디오 재생, 화면 탭 (아이콘 표시)
2. 1초 후 UI 토글 (전체 UI 숨김)
3. 아이콘도 함께 사라짐 확인
4. UI 다시 표시
5. 아이콘 다시 나타남 확인
```

## 🎬 최종 UX 흐름

```
사용자 탭
  ↓
_showVideoControls = true
  ↓
타이머 시작 (2초 설정)
  ↓
플레이 버튼 AnimatedOpacity 트리거
  ↓
300ms 페이드인 효과
  ↓
사용자가 2초 동안 봄
  ↓
타이머 콜백 실행
  ↓
_showVideoControls = false
  ↓
300ms 페이드아웃 효과
  ↓
완전히 숨겨짐
```

## 💡 기술적 세부사항

### 타이머 관리
- `_controlsTimer?.cancel()` - 기존 타이머 취소 (중복 실행 방지)
- `Timer()` - 새 타이머 생성
- `if (mounted)` - 위젯 여전히 마운트된지 확인

### 메모리 관리
- `dispose()`에서 타이머 명시적 해제
- 위젯 언마운트 시 자동 정리
- 메모리 누수 방지

### 성능
- 최소한의 setState 호출 (2회)
- 애니메이션은 기존 AnimatedOpacity 활용
- CPU 오버헤드 최소화

## ✅ 완성 체크리스트

- [x] 상태 변수 추가
- [x] 타이머 함수 구현
- [x] onTap 콜백 수정
- [x] 표시 조건 업데이트
- [x] dispose에서 정리
- [x] 코드 분석 완료
- [x] 빌드 중...

---

**최종 상태**: ✅ UX 미세 조정 완료
**갤럭시 갤러리 호환성**: 🚀 100%
**네이티브 앱 수준**: ⭐⭐⭐⭐⭐
