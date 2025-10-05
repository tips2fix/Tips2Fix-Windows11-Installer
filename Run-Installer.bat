@echo off
setlocal EnableExtensions
chcp 65001 >nul

title Tips2Fix - Windows 11 25H2 Installer (Safe Confirmed Edition)
color 0E
echo.
echo ===============================================
echo        Tips2Fix Windows 11 25H2 Installer
echo -----------------------------------------------
echo     Safe Confirmed Edition (Antivirus Friendly)
echo ===============================================
echo.

REM --- Check for administrator privileges ---
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -ExecutionPolicy RemoteSigned -Command ^
        "Start-Process -FilePath '%~f0' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b
)

REM --- Locate Windows PowerShell 5.1 ---
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS_EXE%" (
    echo PowerShell 5.1 not found on this system!
    pause
    endlocal & exit /b 1
)

REM --- Target script (same folder) ---
set "SCRIPT_PATH=%~dp0Windows11_QuickInstaller.ps1"
if not exist "%SCRIPT_PATH%" (
    echo Missing file: Windows11_QuickInstaller.ps1
    echo Please make sure both files are in the same folder.
    echo.
    pause
    endlocal & exit /b 1
)

REM === GUI popup: ask to Unblock the PS1 (recommended) ===
powershell -NoProfile -ExecutionPolicy RemoteSigned -Command ^
  "Add-Type -AssemblyName System.Windows.Forms; " ^
  "$msg = 'Unblock the PowerShell script before running (recommended)?' + [Environment]::NewLine + [Environment]::NewLine + 'This removes the Internet zone mark so it can run under RemoteSigned.'; " ^
  "$r = [System.Windows.Forms.MessageBox]::Show($msg,'Tips2Fix', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question); " ^
  "if ($r -eq [System.Windows.Forms.DialogResult]::Yes) { exit 0 } else { exit 1 }"

if %errorlevel%==0 (
    echo Unblocking script...
    powershell -NoProfile -ExecutionPolicy RemoteSigned -Command ^
      "Unblock-File -LiteralPath '%SCRIPT_PATH%'"
) else (
    echo Skipping unblock by user choice.
)

echo Launching Tips2Fix installer safely...
"%PS_EXE%" -NoProfile -ExecutionPolicy RemoteSigned -File "%SCRIPT_PATH%"
echo.
echo Installer finished.
echo Log file saved on your Desktop (Tips2Fix_W11_install_log.txt)
echo.

pause
endlocal
exit /b 0
