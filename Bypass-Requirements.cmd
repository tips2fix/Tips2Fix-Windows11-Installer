@echo off
setlocal EnableExtensions
title Tips2Fix - Windows 11 requirement bypass

rem ============================================================================
rem  Tips2Fix Bypass-Requirements.cmd  v1.2.0
rem
rem  Sets or removes the registry values that let Windows 11 Setup run on a PC
rem  Microsoft lists as unsupported. It changes nothing else: no services, no
rem  startup entries, no files in Windows. Every value is listed below.
rem
rem    Double-click        menu (apply, remove, status)
rem    /apply              apply without asking (used by the Tips2Fix installer)
rem    /remove             remove without asking
rem    /status             show what is currently set
rem
rem  Set T2F_DRYRUN=1 to print the commands instead of running them.
rem ============================================================================

set "ACTION=%~1"
set "FAIL=0"
set "RUN="
set "Q=>nul 2>&1"
if defined T2F_DRYRUN (
  set "RUN=echo [dry-run]"
  set "Q="
)

set "K_LAB=HKLM\SYSTEM\Setup\LabConfig"
set "K_MO=HKLM\SYSTEM\Setup\MoSetup"
set "K_HW=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\HwReqChk"
set "K_PCHC=HKCU\Software\Microsoft\PCHC"
set "K_COMPAT=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags"

rem ---- Administrator rights (skipped for dry runs) ---------------------------
if defined T2F_DRYRUN goto :start
fltmc >nul 2>&1 && goto :start

echo Administrator rights are needed. A Windows permission prompt will appear...
set "T2F_SELF=%~f0"
set "T2F_ARGS=%*"
if defined T2F_ARGS (
  powershell -NoProfile -Command "Start-Process -FilePath $env:T2F_SELF -ArgumentList $env:T2F_ARGS -Verb RunAs"
) else (
  powershell -NoProfile -Command "Start-Process -FilePath $env:T2F_SELF -Verb RunAs"
)
exit /b 0

:start
if /i "%ACTION%"=="/apply"  goto :do_apply
if /i "%ACTION%"=="/remove" goto :do_remove
if /i "%ACTION%"=="/status" goto :do_status
if not "%ACTION%"=="" (
  echo Unknown option: %ACTION%
  echo Use /apply, /remove or /status, or run without options for the menu.
  exit /b 2
)

:menu
cls
echo.
echo   Tips2Fix - Windows 11 requirement bypass
echo   ----------------------------------------
echo.
echo     1  Apply the bypass
echo     2  Remove the bypass
echo     3  Show what is currently set
echo     4  Exit
echo.
choice /c 1234 /n /m "  Choose 1-4: "
if errorlevel 4 exit /b 0
if errorlevel 3 goto :menu_status
if errorlevel 2 goto :menu_remove
goto :menu_apply

:menu_apply
echo.
echo   This sets the values listed in the README under "Install from a Windows 11 ISO":
echo   LabConfig, MoSetup, HwReqChk and PCHC. It does not start Windows Setup.
echo.
choice /c YN /n /m "  Apply now? (Y/N): "
if errorlevel 2 goto :menu
call :apply
call :report "applied"
pause
goto :menu

:menu_remove
echo.
echo   This removes the same values and restores the Windows defaults.
echo.
choice /c YN /n /m "  Remove now? (Y/N): "
if errorlevel 2 goto :menu
call :remove
call :report "removed"
pause
goto :menu

:menu_status
call :status
pause
goto :menu

:do_apply
call :apply
call :report "applied"
exit /b %FAIL%

:do_remove
call :remove
call :report "removed"
exit /b %FAIL%

:do_status
call :status
exit /b 0

rem ---- Apply -----------------------------------------------------------------
:apply
echo.
echo   Applying...
for %%V in (BypassTPMCheck BypassSecureBootCheck BypassRAMCheck BypassCPUCheck BypassStorageCheck BypassDiskCheck) do (
  %RUN% reg add "%K_LAB%" /v %%V /t REG_DWORD /d 1 /f %Q% || set "FAIL=1"
)
%RUN% reg add "%K_MO%" /v AllowUpgradesWithUnsupportedTPMOrCPU /t REG_DWORD /d 1 /f %Q% || set "FAIL=1"

rem Makes the compatibility check report a pass. This is what keeps
rem "Keep personal files and apps" available during an upgrade.
%RUN% reg add "%K_HW%" /v HwReqChkVars /t REG_MULTI_SZ /d "SQ_SecureBootCapable=TRUE\0SQ_SecureBootEnabled=TRUE\0SQ_TpmVersion=2\0SQ_RamMB=8192" /f %Q% || set "FAIL=1"
%RUN% reg add "%K_PCHC%" /v UpgradeEligibility /t REG_DWORD /d 1 /f %Q% || set "FAIL=1"

rem Clears the saved result of an earlier failed attempt, which Windows reuses.
for %%S in (CompatMarkers Shared TargetVersionUpgradeExperienceIndicators) do (
  %RUN% reg delete "%K_COMPAT%\%%S" /f %Q%
)
exit /b 0

rem ---- Remove ----------------------------------------------------------------
:remove
echo.
echo   Removing...
for %%V in (BypassTPMCheck BypassSecureBootCheck BypassRAMCheck BypassCPUCheck BypassStorageCheck BypassDiskCheck) do (
  %RUN% reg delete "%K_LAB%" /v %%V /f %Q%
)
%RUN% reg delete "%K_MO%" /v AllowUpgradesWithUnsupportedTPMOrCPU /f %Q%
%RUN% reg delete "%K_HW%" /v HwReqChkVars /f %Q%
%RUN% reg delete "%K_PCHC%" /v UpgradeEligibility /f %Q%

rem Only drop a key when nothing else is left in it.
call :drop_if_empty "%K_LAB%"
call :drop_if_empty "%K_HW%"
exit /b 0

:drop_if_empty
if defined T2F_DRYRUN (
  echo [dry-run] delete key %~1 only if it is empty
  exit /b 0
)
set "LEFT=0"
for /f "skip=1 tokens=*" %%L in ('reg query "%~1" 2^>nul') do set /a LEFT+=1
if "%LEFT%"=="0" reg delete "%~1" /f >nul 2>&1
exit /b 0

rem ---- Status ----------------------------------------------------------------
:status
echo.
echo   Current values (an error line means the value is not set):
echo.
reg query "%K_LAB%" 2>nul || echo   LabConfig: not set
reg query "%K_MO%" /v AllowUpgradesWithUnsupportedTPMOrCPU 2>nul || echo   MoSetup: not set
reg query "%K_HW%" /v HwReqChkVars 2>nul || echo   HwReqChk: not set
reg query "%K_PCHC%" /v UpgradeEligibility 2>nul || echo   PCHC: not set
echo.
exit /b 0

:report
echo.
if "%FAIL%"=="0" (
  echo   Done. The bypass was %~1.
) else (
  echo   Something failed. Make sure this window has administrator rights.
)
echo.
call :writelog "%~1"
exit /b 0

rem One line per run in a Logs folder next to this file. Skipped quietly if the
rem folder cannot be written, and never written during a dry run.
:writelog
if defined T2F_DRYRUN exit /b 0
if not exist "%~dp0Logs" mkdir "%~dp0Logs" >nul 2>&1
2>nul >>"%~dp0Logs\Bypass-Requirements.log" echo [%date% %time%] %~1, result %FAIL% ^(0 = ok^)
exit /b 0
