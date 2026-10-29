@echo off
rem Double-click once to install dependencies and create the Broken Speaker Desktop shortcut.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\setup-tray.ps1"
pause
