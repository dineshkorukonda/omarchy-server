@echo off
setlocal

:: Start the background daemon
start "" /b "%~dp0ssh_client.bat" start

:: Wait briefly for endpoint to warm up
timeout /t 2 /nobreak >nul

:: Launch dedicated standalone app window using Edge/Chrome app mode
set "URL=http://localhost:4000"

:: 1. Try Microsoft Edge in standalone app window mode
where msedge >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    start "" msedge --app="%URL%" --window-size=1120,740
    goto :done
)

:: 2. Try Google Chrome in standalone app window mode
where chrome >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    start "" chrome --app="%URL%" --window-size=1120,740
    goto :done
)

:: 3. Fallback to default browser
start "" "%URL%"

:done
endlocal
