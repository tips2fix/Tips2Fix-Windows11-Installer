@echo off
rem ===============================================
rem   Tips2Fix Windows 11 25H2 Installer
rem   Created in collaboration with ChatGPT
rem ===============================================
echo.

setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT=Windows11_QuickInstaller.ps1"
set "FULLPATH=%~dp0%SCRIPT%"
set "RAW_URL=https://raw.githubusercontent.com/tips2fix/Tips2Fix-Windows11-Installer/main/Windows11_QuickInstaller.ps1"

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
    powershell -NoProfile -Command "try { Invoke-WebRequest -Uri '%RAW_URL%' -UseBasicParsing -OutFile '%FULLPATH%' } catch { Write-Host 'Download failed:' $_; exit 1 }"
    if not exist "%FULLPATH%" (
      echo Download failed. Manually download from:
      echo %RAW_URL%
      pause
      exit /b 1
    )
  )
)

rem 2) Unblock the file (remove Zone.Identifier if downloaded from the internet)
powershell -NoProfile -Command "try { Unblock-File -Path '%FULLPATH%' -ErrorAction SilentlyContinue } catch {}"

rem 3) Make the policy a non-issue (CurrentUser + this Process), no prompts
powershell -NoProfile -Command "try { Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force -ErrorAction SilentlyContinue } catch {}"
powershell -NoProfile -Command "try { Set-ExecutionPolicy -Scope Process Bypass      -Force -ErrorAction SilentlyContinue } catch {}"

rem 4) Launch elevated PowerShell and run the installer with policy bypass
echo Launching installer (it will request Administrator privileges)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath 'powershell' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%FULLPATH%\"' -Verb RunAs"

endlocal
exit /b
