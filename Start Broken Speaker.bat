@echo off
rem Double-click to start streaming. Extra options are passed to app.py, e.g. --device "Headphones"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*
pause
