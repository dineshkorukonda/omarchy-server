@echo off
start "" "%~dp0ssh_client.bat" start
timeout /t 2 /nobreak >nul
start "" "http://localhost:4000"
