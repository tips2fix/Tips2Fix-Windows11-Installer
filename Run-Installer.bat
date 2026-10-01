@echo off
setlocal EnableExtensions
chcp 65001 >nul

rem ===============================================
rem   Tips2Fix Windows 11 26H2 Installer (BAT)
rem   Opens the classic blue Windows PowerShell window.
rem   Does not change the system execution policy.
rem ===============================================

set "SCRIPT=Windows11_QuickInstaller.ps1"
set "FULLPATH=%~dp0%SCRIPT%"
set "RAW_URL=https://raw.githubusercontent.com/tips2fix/Tips2Fix-Windows11-Installer/main/Windows11_QuickInstaller.ps1"

rem PowerShell reads the path from the environment instead of the command line,
rem so apostrophes, ampersands and brackets in folder names cannot break it.
set "T2F_SCRIPT=%FULLPATH%"

echo.
echo Tips2Fix Windows 11 26H2 Installer v1.2.0
echo ------------------------------------------
echo.

rem 1) Make sure the PS1 is here (offer to download it)
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
      "Invoke-WebRequest -Uri '%RAW_URL%' -UseBasicParsing -OutFile $env:T2F_SCRIPT"
    if not exist "%FULLPATH%" (
      echo Download failed. Manually download from:
      echo %RAW_URL%
      pause
      exit /b 1
    )
  )
)

rem 2) Unblock the file quietly (no error if it is not blocked)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try{Unblock-File -LiteralPath $env:T2F_SCRIPT -ErrorAction SilentlyContinue}catch{}"

rem 3) Start a separate elevated Windows PowerShell window and run the PS1
echo Launching installer (UAC prompt will appear)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath ($env:SystemRoot + '\System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoLogo -File \"' + $env:T2F_SCRIPT + '\"') -Verb RunAs -WindowStyle Normal"

endlocal
exit /b 0
