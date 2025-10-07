@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul

rem ===============================================
rem   Tips2Fix Windows 11 25H2 Installer(BAT)
rem   Opens classic blue Windows PowerShell window
rem   AV-friendly (no CurrentUser policy changes)
rem ===============================================

set "SCRIPT=Windows11_QuickInstaller.ps1"
set "FULLPATH=%~dp0%SCRIPT%"
set "RAW_URL=https://raw.githubusercontent.com/tips2fix/Tips2Fix-Windows11-Installer/main/Windows11_QuickInstaller.ps1"

echo.
echo Tips2Fix Windows 11 25H2 Installer v1.0.2
echo ------------------------------------------
echo.

rem 1) Ensure the PS1 exists (offer auto-download)
if exist "%FULLPATH%" (
  echo Found %SCRIPT% in this folder.
) else (
  echo WARNING: %SCRIPT% not found here.
  choice /M "Download it now from the official GitHub repo?"
  if errorlevel 2 (
    echo Please place %SCRIPT% in this folder and run again.
    pause
    exit /b 1
  ) else (
    echo Downloading %SCRIPT%...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
      "$ProgressPreference='SilentlyContinue';" ^
      "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
      "Invoke-WebRequest -Uri '%RAW_URL%' -UseBasicParsing -OutFile '%FULLPATH%'" 
    if not exist "%FULLPATH%" (
      echo Download failed. Manually download from:
      echo %RAW_URL%
      pause
      exit /b 1
    )
  )
)

rem 2) Unblock the file quietly (no error if not blocked)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try{Unblock-File -LiteralPath '%FULLPATH%' -ErrorAction SilentlyContinue}catch{}"

rem 3) Launch a *separate* elevated Windows PowerShell (classic blue) and run the PS1
echo Launching installer (UAC prompt will appear)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-NoLogo','-File','\"%FULLPATH%\"' -Verb RunAs -WindowStyle Normal"

endlocal
exit /b 0
