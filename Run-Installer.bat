@echo off
echo ===============================================
echo   Tips2Fix Windows 11 25H2 Installer
echo   Created in collaboration with ChatGPT
echo ===============================================
echo.

set SCRIPT=Windows11_QuickInstaller.ps1

if not exist "%~dp0%SCRIPT%" (
  echo ERROR: "%SCRIPT%" not found in this folder.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath 'powershell' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0%SCRIPT%\"' -Verb RunAs"

exit /b
