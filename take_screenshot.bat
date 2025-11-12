@echo off
:: 스크린샷 저장 폴더 설정
set SCREENSHOT_DIR=%~dp0\screenshots

:: 스크린샷 폴더가 없으면 생성
if not exist "%SCREENSHOT_DIR%" mkdir "%SCREENSHOT_DIR%"

:: 현재 날짜와 시간으로 파일 이름 생성
for /f "tokens=2 delims==." %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set datetime=%datetime:~0,8%_%datetime:~8,6%

:: flutter screenshot 명령 실행 및 결과 파일 이동
flutter screenshot -o "%SCREENSHOT_DIR%\screenshot_%datetime%.png"

:: 완료 메시지 출력
echo 스크린샷이 %SCREENSHOT_DIR% 폴더에 저장되었습니다.
pause