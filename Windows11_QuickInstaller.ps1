<# 
Tips2Fix
Windows 11 25H2 Quick Installer (Safe Confirmed Edition)
All-in-one PowerShell script (PS 5.1 compatible)
Developed in collaboration with ChatGPT (Tips2Fix Project)
#>

# ===== Bootstrap =====
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()


$ErrorActionPreference = 'Stop'

$AutoContinue  = $false
$QuietCopyLogs = $true

$desktop     = [Environment]::GetFolderPath("Desktop")
$logPath     = Join-Path $desktop "Tips2Fix_W11_install_log.txt"
$scriptStart = Get-Date

# Put near other variables/constants at the top
$SubscribeUrl = 'https://www.youtube.com/channel/UC3kEO7SEulVV__uGbbumQog?sub_confirmation=1'

function Log {
    param([string]$msg)
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "[$t] $msg" | Out-File -FilePath $logPath -Append -Encoding UTF8
    Write-Host "[$t] $msg"
}

# Elevate (safety net – your .bat already elevates)
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "runas"
    try { [System.Diagnostics.Process]::Start($psi) | Out-Null } catch { exit }
    exit
}

"Tips2Fix Windows 11 Installer Log" | Out-File -FilePath $logPath -Force -Encoding UTF8
Log "Script started."

try {
    # ===== Intro (same grid layout, orange title) =====
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Tips2Fix - Windows 11 25H2 Installer"
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox     = $false
    $form.MaximizeBox     = $false
    $form.AutoScaleMode   = 'Dpi'
    $form.MinimumSize     = New-Object System.Drawing.Size(720,190)
    $form.Padding         = New-Object System.Windows.Forms.Padding(10)
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 12)

    $grid = New-Object System.Windows.Forms.TableLayoutPanel
    $grid.Dock = 'Fill'; $grid.RowCount = 4; $grid.ColumnCount = 2
    $grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,80)))
    $grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,20)))
    $grid.AutoSize = $true

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Tips2Fix - Windows 11 25H2 Installer"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(255,140,0)  # ORANGE (original)
    $title.AutoSize = $true
    $title.Margin   = New-Object System.Windows.Forms.Padding(6,6,6,2)
    $grid.Controls.Add($title, 0, 0)
    $grid.SetColumnSpan($title, 2)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = "Backup your files first! Installing on unsupported hardware is risky."
    $sub.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $sub.AutoSize = $true
    $sub.Margin   = New-Object System.Windows.Forms.Padding(6,0,6,8)
    $grid.Controls.Add($sub, 0, 1)
    $grid.SetColumnSpan($sub, 2)

    $footer = New-Object System.Windows.Forms.Label
    $footer.Text = "Developed in collaboration with ChatGPT (Tips2Fix Project)"
    $footer.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $footer.ForeColor = [System.Drawing.Color]::Gray
    $footer.AutoSize = $true
    $footer.Margin   = New-Object System.Windows.Forms.Padding(6,0,6,8)
    $grid.Controls.Add($footer, 0, 2)
    $grid.SetColumnSpan($footer, 2)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "Continue"
    $btn.Width = 140; $btn.Height = 40
    $btn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btn.Anchor = 'Right'
    $btn.Margin = New-Object System.Windows.Forms.Padding(6)
    $grid.Controls.Add($btn, 1, 3)

    if ($AutoContinue) {
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1000
        $sec = 5
        $countLbl = New-Object System.Windows.Forms.Label
        $countLbl.Text = "Auto-continue in $sec..."
        $countLbl.AutoSize = $true
        $grid.Controls.Add($countLbl, 0, 3)
        $timer.Add_Tick({
            $script:sec -= 1
            if ($script:sec -le 0) {
                $timer.Stop(); $form.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.Close()
            } else { $countLbl.Text = "Auto-continue in $script:sec..." }
        })
        $timer.Start()
    }

    $form.Controls.Add($grid)
    $form.AcceptButton = $btn
    $form.Topmost = $true
    if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw "User cancelled at intro." }
    Log "Intro accepted."

    # ===== Mode selection (same wording) =====
    $modeForm = New-Object System.Windows.Forms.Form
    $modeForm.Text = "Select installation mode"
    $modeForm.StartPosition   = "CenterScreen"
    $modeForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $modeForm.MinimizeBox     = $false
    $modeForm.MaximizeBox     = $false
    $modeForm.AutoScaleMode   = 'Dpi'
    $modeForm.MinimumSize     = New-Object System.Drawing.Size(760,280)
    $modeForm.Padding         = New-Object System.Windows.Forms.Padding(10)
    $modeForm.Font            = New-Object System.Drawing.Font("Segoe UI", 12)

    $tbl = New-Object System.Windows.Forms.TableLayoutPanel
    $tbl.Dock = 'Fill'; $tbl.RowCount = 5; $tbl.ColumnCount = 1; $tbl.AutoSize = $true

    $rb1 = New-Object System.Windows.Forms.RadioButton
    $rb1.Text = "1) Fast install / upgrade (no registry edits)"
    $rb1.Checked = $true; $rb1.AutoSize = $true

    $rb2 = New-Object System.Windows.Forms.RadioButton
    $rb2.Text = "2) Advanced install (apply bypass registry keys)"
    $rb2.AutoSize = $true

    $rb3 = New-Object System.Windows.Forms.RadioButton
    $rb3.Text = "3) Reset registry keys to original (remove bypass)"
    $rb3.AutoSize = $true

    $tbl.Controls.Add($rb1); $tbl.Controls.Add($rb2); $tbl.Controls.Add($rb3)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"; $ok.Width = 140; $ok.Height = 40; $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $tbl.Controls.Add($ok)

    $modeForm.Controls.Add($tbl)
    $modeForm.AcceptButton = $ok
    $modeForm.Topmost = $true
    if ($modeForm.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw "User cancelled at mode selection." }

    $selectedMode = if ($rb2.Checked) { "advanced" } elseif ($rb3.Checked) { "reset" } else { "fast" }
    Log "Mode selected: $selectedMode"

    # ===== Registry helpers =====
    function Apply-Bypass {
        Log "Applying bypass keys..."
        New-Item -Path "HKLM:\SYSTEM\Setup\LabConfig" -Force | Out-Null
        Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassTPMCheck"        -Value 1 -Type DWord
        Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassSecureBootCheck" -Value 1 -Type DWord
        Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassRAMCheck"        -Value 1 -Type DWord
        Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassCPUCheck"        -Value 1 -Type DWord
        New-Item -Path "HKLM:\SYSTEM\Setup\MoSetup" -Force | Out-Null
        Set-ItemProperty "HKLM:\SYSTEM\Setup\MoSetup" -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Value 1 -Type DWord
        Log "Bypass registry keys applied successfully."
    }
    function Reset-Bypass {
        Log "Resetting bypass keys..."
        Remove-Item -Path "HKLM:\SYSTEM\Setup\LabConfig" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SYSTEM\Setup\MoSetup" -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -ErrorAction SilentlyContinue
        Log "Bypass keys reset."
    }

    switch ($selectedMode) {
        "advanced" {
            $resp = [System.Windows.Forms.MessageBox]::Show(
                "You chose 'Advanced Install'. This applies bypass keys (TPM, CPU, RAM, Secure Boot). Continue?",
                "Confirm - Apply Bypass",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            if ($resp -eq [System.Windows.Forms.DialogResult]::Yes) {
                Apply-Bypass
                [System.Windows.Forms.MessageBox]::Show("Bypass registry keys applied.","Tips2Fix",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
        }
        "reset" {
            $resp = [System.Windows.Forms.MessageBox]::Show(
                "Remove bypass keys and restore defaults?",
                "Confirm - Reset Registry",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($resp -eq [System.Windows.Forms.DialogResult]::Yes) {
                Reset-Bypass
                [System.Windows.Forms.MessageBox]::Show("Registry reset completed.","Tips2Fix",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                exit
            }
        }
        default { }
    }

    # ===== ISO picker =====
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "ISO files (*.iso)|*.iso"
    $ofd.Title  = "Select Windows 11 25H2 ISO"
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw "User cancelled ISO picker." }
    $isoPath = $ofd.FileName
    $isoName = [System.IO.Path]::GetFileNameWithoutExtension($isoPath)
    $dest    = Join-Path $desktop $isoName
    if (-not (Test-Path $dest)) { New-Item -Path $dest -ItemType Directory | Out-Null }
    Log "ISO selected: $isoPath"
    Log "Destination: $dest"

# After:
# $isoPath = $ofd.FileName
# $isoName = [System.IO.Path]::GetFileNameWithoutExtension($isoPath)
# $dest    = Join-Path $desktop $isoName

# --- Confirm extraction location (Desktop\<ISO name>) ---
$confirmText = "Windows 11 ISO `"${isoName}`" will be extracted to your Desktop:`n`n$dest`n`nDo you want to proceed?"
$confirmExtract = [System.Windows.Forms.MessageBox]::Show(
    $confirmText,
    "Confirm Extraction",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

if ($confirmExtract -ne [System.Windows.Forms.DialogResult]::Yes) {
    # Optional: offer to choose a different folder instead of cancelling
    $choose = [System.Windows.Forms.MessageBox]::Show(
        "Do you want to pick a different destination folder?",
        "Choose Different Folder",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($choose -eq [System.Windows.Forms.DialogResult]::Yes) {
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Select a folder in which to create: ${isoName}"
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $dest = Join-Path $fbd.SelectedPath $isoName
        } else {
            throw "User cancelled extraction location."
        }
    } else {
        throw "User cancelled extraction."
    }
}

# Ensure destination exists
if (-not (Test-Path -LiteralPath $dest)) {
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
}

    # ===== Mount ISO (robust) =====
    Log "Mounting ISO..."
    $disk = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
    $drive = $null
    for ($i=0; $i -lt 60; $i++) {
        try {
            $vol = Get-Volume -DiskImage $disk -ErrorAction SilentlyContinue | Where-Object DriveLetter
            if ($vol -and $vol.DriveLetter) {
                $drive = "$($vol.DriveLetter):"
                if (Test-Path "$drive\") { break }
            }
        } catch {}
        Start-Sleep -Seconds 1
    }
    if (-not $drive) { throw "ISO mount failed or no drive letter was assigned." }
    Log "Mounted at $drive"

    # ===== Extraction Progress (deterministic copy, live %) =====
$progForm = New-Object System.Windows.Forms.Form
$progForm.Text = "Extracting ISO Files..."
$progForm.StartPosition = "CenterScreen"
$progForm.Width = 540
$progForm.Height = 160
$progForm.Font = New-Object System.Drawing.Font("Segoe UI", 11)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(10,20)
$bar.Width = 500
$bar.Maximum = 100
$bar.Minimum = 0
$progForm.Controls.Add($bar)

$lbl = New-Object System.Windows.Forms.Label
$lbl.Location = New-Object System.Drawing.Point(10,60)
$lbl.AutoSize = $true
$lbl.Text = "Preparing..."
$progForm.Controls.Add($lbl)
$progForm.Topmost = $true
$progForm.Show()

# Make sure ISO root has a trailing backslash so Substring math is correct
$isoRoot = if ($drive.EndsWith(':')) { "$drive\" } else { $drive }

# Count total files for progress % (include hidden/system)
$total = (Get-ChildItem -LiteralPath $isoRoot -Recurse -Force |
          Where-Object { -not $_.PSIsContainer }).Count
if ($total -eq 0) { $total = 1 }

$filesCopied = 0
Get-ChildItem -LiteralPath $isoRoot -Recurse -Force | ForEach-Object {
    if ($_.PSIsContainer) {
        # Create directory in destination
        $rel    = $_.FullName.Substring($isoRoot.Length)
        $target = Join-Path $dest $rel
        if (-not (Test-Path -LiteralPath $target)) {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
        }
    }
    else {
        # Build target path (preserve structure)
        $rel    = $_.FullName.Substring($isoRoot.Length)
        $target = Join-Path $dest $rel
        $tDir   = Split-Path $target -Parent
        if (-not (Test-Path -LiteralPath $tDir)) {
            New-Item -ItemType Directory -Force -Path $tDir | Out-Null
        }

        try {
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force -ErrorAction Stop
        } catch {
            Log "WARN: Failed to copy $($_.FullName) -> $target : $_"
        }

        $filesCopied++
        $percent = [Math]::Min(100, [Math]::Round(($filesCopied / $total) * 100))
        $bar.Value = $percent
        $lbl.Text  = "Extracting... $percent% ($filesCopied / $total)"
        [System.Windows.Forms.Application]::DoEvents()
    }
}

$progForm.Close()
Log "Extraction completed successfully to $dest."

# Dismount ISO
try { Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue } catch {}

# Verify setup files exist (setupprep.exe preferred, then setup.exe)
$setup = $null
$setupPrep = Join-Path $dest "sources\setupprep.exe"
$setupExe  = Join-Path $dest "setup.exe"
if (Test-Path -LiteralPath $setupPrep) { $setup = $setupPrep }
elseif (Test-Path -LiteralPath $setupExe) { $setup = $setupExe }

if (-not $setup) {
    [System.Windows.Forms.MessageBox]::Show(
        "Setup files not found in the extracted folder.`nFolder:`n$dest",
        "Tips2Fix",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    Log "ERROR: Setup files not found in $dest"
    exit
}


# ===== Confirm and start Setup =====
# We already validated $setup above, so no need to re-detect here.
$confirmSetup = [System.Windows.Forms.MessageBox]::Show(
    "Do you want to start Windows 11 Setup now?",
    "Confirm Setup",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

if ($confirmSetup -eq [System.Windows.Forms.DialogResult]::Yes) {
    Log "Launching setup: $setup /product server"
    Start-Process -FilePath $setup -ArgumentList "/product server" -Verb RunAs

    # Console-only cleanup note
    Write-Host ""
    Write-Host "When Windows installation is completely finished, you can safely delete the extracted folder:" -ForegroundColor Yellow
    Write-Host "  $dest"
    Log "Cleanup note shown for: $dest"

    # Single dialog: success + subscribe
    $msg = "Installation started successfully." +
           "`n`nEnjoy Windows 11 25H2" +
           "`n`nWould you like to open the Tips2Fix YouTube channel and subscribe?"

    $openSub = [System.Windows.Forms.MessageBox]::Show(
        $msg,
        "Tips2Fix",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    if ($openSub -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Start-Process $SubscribeUrl
            Log "Opened YouTube subscribe link."
        } catch {
            Log "Could not open YouTube link: $_"
        }
    }

}

    Log "Finished. Duration: $((Get-Date) - $scriptStart)"
}
catch {
    Log "ERROR: $_"
    try {
        [System.Windows.Forms.MessageBox]::Show(
            "An error occurred:`n$_`nCheck the log at:`n$logPath",
            "Tips2Fix Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch { }
}
finally {
    Read-Host "Script finished. Press Enter to close this window..."
}


