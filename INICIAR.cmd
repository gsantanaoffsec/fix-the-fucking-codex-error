@echo off
setlocal
title Codex Doctor - Diagnosticar e Corrigir
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CodexDoctor.ps1" -Mode Repair
if errorlevel 1 pause
endlocal
