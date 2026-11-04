@echo off
setlocal
title Codex Doctor - Restaurar Cache
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CodexDoctor.ps1" -Mode Restore
if errorlevel 1 pause
endlocal
