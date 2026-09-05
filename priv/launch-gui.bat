@echo off
setlocal

:: Start the background daemon
start "" /b "%~dp0ssh_client.bat" start

:: Wait briefly for endpoint to warm up
timeout /t 2 /nobreak >nul

set "URL=http://localhost:4000"

:: 1. Try Microsoft Edge in standalone app window mode
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" (
    start "" "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" --app="%URL%" --window-size=1120,740
    goto :done
)

if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" (
    start "" "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" --app="%URL%" --window-size=1120,740
    goto :done
)

where msedge >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    start "" msedge --app="%URL%" --window-size=1120,740
    goto :done
)

:: 2. Try Google Chrome in standalone app window mode
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" (
    start "" "%ProgramFiles%\Google\Chrome\Application\chrome.exe" --app="%URL%" --window-size=1120,740
    goto :done
)

if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" (
    start "" "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" --app="%URL%" --window-size=1120,740
    goto :done
)

if exist "%LocalAppData%\Google\Chrome\Application\chrome.exe" (
    start "" "%LocalAppData%\Google\Chrome\Application\chrome.exe" --app="%URL%" --window-size=1120,740
    goto :done
)

where chrome >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    start "" chrome --app="%URL%" --window-size=1120,740
    goto :done
)

:: 3. Fallback to default browser
start "" "%URL%"

:done
endlocal
