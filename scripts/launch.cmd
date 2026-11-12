@echo off
REM Launch portable, unmanaged Chromium with a profile next to this script.
REM Nothing is written outside this folder: no registry keys beyond the browser's
REM own defaults, no services, no scheduled tasks, no updater.
setlocal

set "HERE=%~dp0"
set "PROFILE=%HERE%profile"
set "BIN=%HERE%chromium\chrome.exe"

if not exist "%BIN%" (
  echo chromium binary missing: %BIN%
  exit /b 1
)

if not exist "%PROFILE%\Default" mkdir "%PROFILE%\Default"
if not exist "%PROFILE%\Default\Preferences" (
  if exist "%HERE%config\preferences.json" (
    copy /y "%HERE%config\preferences.json" "%PROFILE%\Default\Preferences" >nul
  )
)

start "" "%BIN%" ^
  --user-data-dir="%PROFILE%" ^
  --no-first-run ^
  --no-default-browser-check ^
  --disable-background-networking ^
  --disable-component-update ^
  --disable-domain-reliability ^
  --disable-sync ^
  --no-pings ^
  --disable-breakpad ^
  --disable-client-side-phishing-detection ^
  --disable-features=OptimizationHints,MediaRouter,InterestFeedContentSuggestions,Translate,AutofillServerCommunication ^
  %*

endlocal
