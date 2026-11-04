@echo off
setlocal
title Codex Doctor - Somente Diagnostico
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CodexDoctor.ps1" -Mode Diagnose
if errorlevel 1 pause
endlocal
