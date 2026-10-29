@echo off
rem Double-click to start streaming. Extra options are passed through, e.g. --device "Headphones"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\start.ps1" %*
pause
