@echo off
REM Tips2Fix + ChatGPT - Windows 11 25H2 Installer
REM Double-click this file. It will request elevation and run the PowerShell script.

set SCRIPT=Windows11_QuickInstaller.ps1

if not exist "%~dp0%SCRIPT%" (
  echo ERROR: "%SCRIPT%" not found in this folder.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath 'powershell' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0%SCRIPT%\"' -Verb RunAs"

exit /b
