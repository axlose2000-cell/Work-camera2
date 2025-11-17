# 업무용 사진/갤러리 관리 앱 - Copilot Instructions

## 프로젝트 개요
이 프로젝트는 **업무용 사진과 갤러리를 효율적으로 관리하기 위한 Flutter 애플리케이션**입니다.
- **플랫폼**: Android, iOS, Web
- **주요 목적**: 업무 현장에서 사진/비디오 촬영 및 관리
- **언어**: Dart (Flutter SDK 3.9.2+)

## 프로젝트 구조

### 핵심 컴포넌트
```
lib/
├── main.dart           # 앱 진입점, Google Mobile Ads 초기화
├── camera_screen.dart  # 카메라 촬영 화면 (사진/비디오)
├── gallery_screen.dart # 갤러리 보기 및 관리 화면
└── media_viewer.dart   # 미디어 상세 뷰어 (확대/축소, 비디오 재생)
```

### 주요 기능
1. **카메라 기능**
   - 사진 촬영 및 비디오 녹화
   - 플래시 제어, 카메라 전환 (전면/후면)
   - 촬영 타이머 (0-10초)
   - 그리드 오버레이
   - 음소거 옵션

2. **갤러리 기능**
   - 갤럭시 스타일 갤러리 뷰
   - 듀얼 PageController (메인 뷰어 + 필름스트립)
   - 이미지 확대/축소 (PhotoView)
   - 비디오 재생 (VideoPlayer)
   - 휴지통 시스템 (삭제/복원/영구삭제)

3. **광고 통합**
   - Google Mobile Ads (AdMob)
   - 배너 광고 및 인터스티셜 광고

## 개발 가이드라인

### Flutter 개발 규칙
- **Null Safety**: 모든 코드는 null safety를 준수해야 함
- **State Management**: setState()를 사용한 기본 상태 관리
- **비동기 처리**: Future/async-await 패턴 사용
- **리소스 관리**: dispose()에서 모든 컨트롤러와 리소스 해제 필수

### 주요 의존성
```yaml
camera: ^0.10.5+9              # 카메라 기능
photo_manager: ^3.7.1          # 갤러리 자산 관리
photo_view: ^0.15.0            # 이미지 확대/축소
video_player: ^2.5.0           # 비디오 재생
path_provider: ^2.1.3          # 파일 경로
permission_handler: ^11.3.1    # 권한 관리
google_mobile_ads: ^6.0.0      # 광고
```

### 코드 작성 규칙
1. **메모리 관리**: 비디오 컨트롤러는 최대 3개까지만 캐싱
2. **성능 최적화**: 불필요한 setState() 호출 최소화
3. **에러 처리**: try-catch로 모든 비동기 작업 보호
4. **생명주기**: WidgetsBindingObserver를 통한 앱 생명주기 관리
5. **권한 처리**: Android 12+ 분리된 권한 (PHOTO, VIDEO) 고려

### 테스트 및 빌드
- **테스트**: `flutter test`
- **빌드**: `flutter build apk` (Android), `flutter build ios` (iOS)
- **린트**: `flutter analyze`
- **실행**: `flutter run`

## 작업 시 주의사항

### 카메라 관련
- 카메라 초기화 실패 시 사용자에게 명확한 에러 메시지 표시
- 카메라가 없는 기기에서의 대체 처리 필요
- 화면 회전 시 카메라 프리뷰 재조정

### 갤러리 관련
- 대량의 미디어 파일 로드 시 페이지네이션 적용
- 썸네일 캐싱으로 성능 최적화
- 휴지통 모드와 일반 모드 간 상태 관리 명확히

### 광고 관련
- 테스트 환경에서는 테스트 광고 ID 사용
- 광고 로드 실패 시 앱 기능에 영향 없도록 처리

## 알려진 이슈 및 해결 방법
- **AsyncMissingMethod**: 카메라 초기화 전 dispose 호출 방지
- **메모리 폭증**: 비디오 컨트롤러 무제한 캐싱 방지 (최대 3개)
- **권한 문제**: AndroidManifest.xml에 Android 12+ 권한 명시
- **null 안전성**: null 체크 후 `!` 연산자 사용

## 프로젝트 상태
- ✅ **Production Ready**: 모든 핵심 기능 구현 완료
- ✅ **Compile Errors**: 0개
- ✅ **Critical/High Priority**: 100% 완료

## 커뮤니케이션 규칙
- 코드 변경 시 최소한의 수정만 수행
- 기존 작동하는 코드는 건드리지 않음
- 간결하고 명확한 설명 유지
- 한국어로 사용자와 소통
