<#
Tips2Fix + ChatGPT
Windows 11 25H2 Premium Quick Installer
All-in-one PowerShell script (ready for PS2EXE packaging)
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$desktop = [Environment]::GetFolderPath("Desktop")
$logPath = Join-Path $desktop "Tips2Fix_W11_install_log.txt"
$ScriptStart = Get-Date

function Log { 
    param($msg)
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$t] $msg"
    $line | Out-File -FilePath $logPath -Append -Encoding UTF8
    Write-Host $line
}

# --- Elevation check ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo "PowerShell";
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"";
    $psi.Verb = "runas";
    try { [System.Diagnostics.Process]::Start($psi) } catch { exit }
    exit
}

"Tips2Fix Windows11 Installer Log" | Out-File -FilePath $logPath -Force -Encoding UTF8
Log "Script started."

# --- Intro Form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Tips2Fix — Windows 11 25H2 Installer"
$form.Width = 640
$form.Height = 120
$form.StartPosition = "CenterScreen"

$lbl = New-Object System.Windows.Forms.Label
$lbl.Text = "Tips2Fix + ChatGPT — Windows 11 25H2 Premium Installer"
$lbl.Font = New-Object System.Drawing.Font("Segoe UI",11,[System.Drawing.FontStyle]::Bold)
$lbl.AutoSize = $true
$lbl.ForeColor = [System.Drawing.Color]::FromArgb(255,140,0) # orange
$lbl.Location = New-Object System.Drawing.Point(10,10)
$form.Controls.Add($lbl)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = "Backup your files first! Installing on unsupported hardware is risky."
$sub.Font = New-Object System.Drawing.Font("Segoe UI",9)
$sub.AutoSize = $true
$sub.Location = New-Object System.Drawing.Point(10,40)
$form.Controls.Add($sub)

$btn = New-Object System.Windows.Forms.Button
$btn.Text = "Continue"
$btn.Width = 100
$btn.Location = New-Object System.Drawing.Point(520,60)
$btn.Add_Click({ $form.Tag = "ok"; $form.Close() })
$form.Topmost = $true
$form.ShowDialog() | Out-Null
if ($form.Tag -ne "ok") { exit }

# --- Mode Selection ---
$modeForm = New-Object System.Windows.Forms.Form
$modeForm.Text = "Select installation mode"
$modeForm.Width = 680
$modeForm.Height = 260
$modeForm.StartPosition = "CenterScreen"

$rb1 = New-Object System.Windows.Forms.RadioButton
$rb1.Text = "1) Fast install / upgrade (no registry edits)"
$rb1.Location = New-Object System.Drawing.Point(20,20)
$rb1.Checked = $true
$modeForm.Controls.Add($rb1)

$rb2 = New-Object System.Windows.Forms.RadioButton
$rb2.Text = "2) Advanced install (apply bypass registry keys)"
$rb2.Location = New-Object System.Drawing.Point(20,50)
$modeForm.Controls.Add($rb2)

$rb3 = New-Object System.Windows.Forms.RadioButton
$rb3.Text = "3) Reset registry keys to original (remove bypass)"
$rb3.Location = New-Object System.Drawing.Point(20,80)
$modeForm.Controls.Add($rb3)

$argLabel = New-Object System.Windows.Forms.Label
$argLabel.Text = "Extra installer args (optional, e.g. /Compat IgnoreWarning)"
$argLabel.Location = New-Object System.Drawing.Point(20,120)
$argLabel.AutoSize = $true
$modeForm.Controls.Add($argLabel)

$argBox = New-Object System.Windows.Forms.TextBox
$argBox.Location = New-Object System.Drawing.Point(20,140)
$argBox.Width = 620
$modeForm.Controls.Add($argBox)

$ok = New-Object System.Windows.Forms.Button
$ok.Text = "OK"
$ok.Location = New-Object System.Drawing.Point(560,180)
$ok.Add_Click({ $modeForm.Tag = "ok"; $modeForm.Close() })
$modeForm.Controls.Add($ok)

$modeForm.Topmost = $true
$modeForm.ShowDialog() | Out-Null
if ($modeForm.Tag -ne "ok") { exit }

$selectedMode = if ($rb2.Checked) { "advanced" } elseif ($rb3.Checked) { "reset" } else { "fast" }
$extraArgs = $argBox.Text.Trim()
Log "Mode: $selectedMode"
if ($extraArgs) { Log "Extra args: $extraArgs" }

# --- ISO Picker ---
$ofd = New-Object System.Windows.Forms.OpenFileDialog
$ofd.Filter = "ISO files (*.iso)|*.iso"
$ofd.Title = "Select Windows 11 25H2 ISO"
if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit }
$isoPath = $ofd.FileName
$isoName = [System.IO.Path]::GetFileNameWithoutExtension($isoPath)
$dest = Join-Path $desktop $isoName
if (-not (Test-Path $dest)) { New-Item -Path $dest -ItemType Directory | Out-Null }
Log "ISO selected: $isoPath"
Log "Destination: $dest"

# --- Mount ISO ---
$volBefore = Get-Volume
Mount-DiskImage -ImagePath $isoPath -ErrorAction Stop
Start-Sleep -Seconds 1
$volAfter = Get-Volume
$driveLetter = ($volAfter | Where-Object { $volBefore.DriveLetter -notcontains $_.DriveLetter -and $_.DriveLetter }).DriveLetter
if (-not $driveLetter) {
    $cd = Get-Volume | Where-Object DriveType -eq 'CDROM' | Select-Object -First 1
    $driveLetter = $cd.DriveLetter
}
$driveLetter = "$driveLetter:"
Log "Mounted at $driveLetter"

# --- Live Progress Copy ---
$totalFiles = (Get-ChildItem -Path "$driveLetter\" -Recurse -Force | ? { -not $_.PSIsContainer }).Count
if ($totalFiles -eq 0) { $totalFiles = 1 }

$progForm = New-Object System.Windows.Forms.Form
$progForm.Text = "Copying ISO files..."
$progForm.Width = 500
$progForm.Height = 120
$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(10,20)
$bar.Width = 460
$bar.Minimum = 0; $bar.Maximum = 100
$progForm.Controls.Add($bar)
$lblProg = New-Object System.Windows.Forms.Label
$lblProg.Location = New-Object System.Drawing.Point(10,60)
$lblProg.AutoSize = $true
$lblProg.Text = "Starting copy..."
$progForm.Controls.Add($lblProg)
$progForm.Topmost = $true
$progForm.Show()

$robocmd = "robocopy ""$driveLetter\ """"$dest\ "" /MIR /R:3 /W:5 /NJH /NJS /NP"
$proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $robocmd" -WindowStyle Hidden -PassThru

while (-not $proc.HasExited) {
    $done = (Get-ChildItem -Path $dest -Recurse -Force | ? { -not $_.PSIsContainer }).Count
    $percent = [Math]::Min(100,[Math]::Round(($done/$totalFiles)*100))
    $bar.Value = $percent
    $lblProg.Text = "Copying... $percent% complete"
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 500
}
$progForm.Close()
Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
Log "Copy finished."

# --- Registry functions ---
function Apply-Bypass {
    Log "Applying bypass keys..."
    New-Item -Path "HKLM:\SYSTEM\Setup\LabConfig" -Force | Out-Null
    Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassTPMCheck" -Value 1 -Type DWord
    Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassSecureBootCheck" -Value 1 -Type DWord
    Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassRAMCheck" -Value 1 -Type DWord
    Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassCPUCheck" -Value 1 -Type DWord
    New-Item -Path "HKLM:\SYSTEM\Setup\MoSetup" -Force | Out-Null
    Set-ItemProperty "HKLM:\SYSTEM\Setup\MoSetup" -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -Value 1 -Type DWord
}
function Reset-Bypass {
    Log "Resetting keys..."
    Remove-Item -Path "HKLM:\SYSTEM\Setup\LabConfig" -Recurse -Force -ErrorAction SilentlyContinue
    try { Remove-ItemProperty -Path "HKLM:\SYSTEM\Setup\MoSetup" -Name "AllowUpgradesWithUnsupportedTPMOrCPU" -ErrorAction SilentlyContinue } catch {}
}

switch ($selectedMode) {
    "advanced" { Apply-Bypass }
    "reset" { Reset-Bypass; [System.Windows.Forms.MessageBox]::Show("Registry reset complete.","Tips2Fix",[System.Windows.Forms.MessageBoxButtons]::OK); exit }
}

# --- Run installer ---
$sources = Join-Path $dest "sources"
$exe = if (Test-Path (Join-Path $sources "setupprep.exe")) { Join-Path $sources "setupprep.exe" } else { Join-Path $sources "setup.exe" }
$args = "/product server"
if ($extraArgs) { $args = "$args $extraArgs" }

Log "Launching $exe $args"
Start-Process -FilePath $exe -ArgumentList $args -Verb RunAs -Wait

# --- Final message ---
$msg = "Enjoy Windows 11 25H2!`nDon't forget to subscribe to Tips2Fix.`n(Unsupported hardware installs are at your own risk)."
[System.Windows.Forms.MessageBox]::Show($msg,"Done — Tips2Fix",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
Log "Finished. Duration: $((Get-Date)-$ScriptStart)"
