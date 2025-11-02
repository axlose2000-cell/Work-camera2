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

## 내일(우선순위) 작업 항목

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

- `lib/media_viewer.dart`: 썸네일 스트립과 LinearProgressIndicator 사이의 간격을 16px에서 20px로 조정하여 UI 개선.
- GitHub 리모트 URL 업데이트: https://github.com/axlose2000-cell/Work-camera.git 연결 확인 및 설정 완료.
- 채팅 기록 저장 방법 문서 생성: `CHAT_HISTORY_2025-10-24.md` 파일에 저장 방법 및 예제 추가.

### 다음 작업 예정

- 디바이스에서 앱 실행 후 검증:
  - 썸네일 표시, 비디오 초기화, 광고 로드 동작 확인.
  - 로그 수집 및 분석.
- iOS Info.plist 설정 확인:
  - AdMob/ATS 항목을 최소 권한으로 적용.
- AdMob 실배너 ID 적용:
  - 프로덕션 광고 유닛 ID로 교체 및 동작 확인.
