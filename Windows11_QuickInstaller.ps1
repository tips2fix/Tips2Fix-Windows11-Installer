<#
Tips2Fix
Windows 11 25H2 Quick Installer
All-in-one PowerShell script (PS 5.1 compatible)
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$AutoContinue   = $false     # set to $true to auto-continue intro after 5 seconds
$SubscribeUrl   = 'https://www.youtube.com/channel/UC3kEO7SEulVV__uGbbumQog?sub_confirmation=1'
$QuietCopyLogs  = $true       # hide noisy robocopy attempt lines in console log

$desktop     = [Environment]::GetFolderPath("Desktop")
$logPath     = Join-Path $desktop "Tips2Fix_W11_install_log.txt"
$scriptStart = Get-Date

function Log {
    param([string]$msg)
    $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$t] $msg"
    $line | Out-File -FilePath $logPath -Append -Encoding UTF8
    Write-Host $line
}

function Open-Url-NewWindow {
    param([Parameter(Mandatory)][string]$Url)

    # Try to detect default browser ProgId
    $progId = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice' -ErrorAction SilentlyContinue).ProgId

    # Build candidates (force NEW WINDOW)
    $candidates = @()

    if ($progId -match 'Chrome') {
        $candidates += @(
          @{Path="$env:ProgramFiles\Google\Chrome\Application\chrome.exe"; Args=@('--new-window', $Url)},
          @{Path="$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"; Args=@('--new-window', $Url)}
        )
    } elseif ($progId -match 'MSEdge') {
        $candidates += @(
          @{Path="$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"; Args=@('--new-window', $Url)},
          @{Path="$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe"; Args=@('--new-window', $Url)}
        )
    } elseif ($progId -match 'Firefox') {
        $candidates += @(
          @{Path="$env:ProgramFiles\Mozilla Firefox\firefox.exe"; Args=@('-new-window', $Url)},
          @{Path="$env:ProgramFiles(x86)\Mozilla Firefox\firefox.exe"; Args=@('-new-window', $Url)}
        )
    } elseif ($progId -match 'Brave') {
        $candidates += @(
          @{Path="$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe"; Args=@('--new-window', $Url)},
          @{Path="$env:ProgramFiles(x86)\BraveSoftware\Brave-Browser\Application\brave.exe"; Args=@('--new-window', $Url)}
        )
    } elseif ($progId -match 'Opera') {
        $candidates += @(
          @{Path="$env:ProgramFiles\Opera\launcher.exe"; Args=@('--new-window', $Url)},
          @{Path="$env:ProgramFiles(x86)\Opera\launcher.exe"; Args=@('--new-window', $Url)}
        )
    } elseif ($progId -match 'Vivaldi') {
        $candidates += @(
          @{Path="$env:ProgramFiles\Vivaldi\Application\vivaldi.exe"; Args=@('--new-window', $Url)},
          @{Path="$env:ProgramFiles(x86)\Vivaldi\Application\vivaldi.exe"; Args=@('--new-window', $Url)}
        )
    }

    # Generic fallbacks
    $candidates += @(
      @{Path="$env:ProgramFiles\Google\Chrome\Application\chrome.exe"; Args=@('--new-window', $Url)},
      @{Path="$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"; Args=@('--new-window', $Url)},
      @{Path="$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"; Args=@('--new-window', $Url)},
      @{Path="$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe"; Args=@('--new-window', $Url)},
      @{Path="$env:ProgramFiles\Mozilla Firefox\firefox.exe"; Args=@('-new-window', $Url)}
    )

    foreach ($c in $candidates) {
        if (Test-Path $c.Path) {
            try {
                Start-Process -FilePath $c.Path -ArgumentList $c.Args -ErrorAction Stop | Out-Null
                return
            } catch { }
        }
    }

    # Last resort: default handler (may open a tab)
    Start-Process $Url | Out-Null
}

# Elevate if needed (safety net; the .bat already elevates)
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo "PowerShell"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb      = "runas"
    try { [System.Diagnostics.Process]::Start($psi) | Out-Null } catch {
        Write-Host "Elevation failed: $_"
        Read-Host "Press Enter to exit..."
        exit
    }
    exit
}

"Tips2Fix Windows 11 Installer Log" | Out-File -FilePath $logPath -Force -Encoding UTF8
Log "Script started."

# ---- CPU feature detector (POPCNT & SSE4.2) ----
function Get-CPUFeatures {
    # Only check when running in 64-bit PowerShell (the inline machine code is x64)
    if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        return $null  # skip check on non-x64 sessions
    }

    $cpuHelperSource = @"
using System;
using System.Runtime.InteropServices;

public static class CpuFeature
{
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate uint Cpuid1EcxDelegate();

    [DllImport("kernel32", SetLastError=true)]
    static extern IntPtr VirtualAlloc(IntPtr lpAddress, UIntPtr dwSize, uint flAllocationType, uint flProtect);

    [DllImport("kernel32", SetLastError=true)]
    static extern bool VirtualFree(IntPtr lpAddress, UIntPtr dwSize, uint dwFreeType);

    const uint MEM_COMMIT  = 0x1000;
    const uint MEM_RESERVE = 0x2000;
    const uint PAGE_EXECUTE_READWRITE = 0x40;
    const uint MEM_RELEASE = 0x8000;

    // Returns CPUID leaf 1 ECX (feature bits)
    public static uint GetCpuid1Ecx()
    {
        // x64 machine code:
        // push rbx
        // mov  eax, 1
        // cpuid
        // mov  eax, ecx
        // pop  rbx
        // ret
        byte[] code = new byte[] {
            0x53,
            0xB8, 0x01,0x00,0x00,0x00,
            0x0F, 0xA2,
            0x89, 0xC8,
            0x5B,
            0xC3
        };

        IntPtr mem = VirtualAlloc(IntPtr.Zero, (UIntPtr)code.Length, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
        if (mem == IntPtr.Zero) throw new Exception("VirtualAlloc failed");
        Marshal.Copy(code, 0, mem, code.Length);
        var del = (Cpuid1EcxDelegate)Marshal.GetDelegateForFunctionPointer(mem, typeof(Cpuid1EcxDelegate));
        uint ecx = del();
        VirtualFree(mem, UIntPtr.Zero, MEM_RELEASE);
        return ecx;
    }

    public static bool HasSse42()  { return ((GetCpuid1Ecx() >> 20) & 1) == 1; } // ECX bit 20
    public static bool HasPopcnt() { return ((GetCpuid1Ecx() >> 23) & 1) == 1; } // ECX bit 23
}
"@

    # Compile once
    $loaded = [AppDomain]::CurrentDomain.GetAssemblies() |
              ForEach-Object { $_.GetTypes() } |
              Where-Object { $_.FullName -eq 'CpuFeature' }
    if (-not $loaded) {
        Add-Type -TypeDefinition $cpuHelperSource -Language CSharp -ErrorAction Stop
    }

    # Return a simple object
    [pscustomobject]@{
        SSE42  = [CpuFeature]::HasSse42()
        POPCNT = [CpuFeature]::HasPopcnt()
    }
}

function Show-CPUCheckDialog {
    param(
        [bool]$HasSSE42,
        [bool]$HasPOPCNT
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "CPU feature check"
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = 'FixedDialog'
    $form.MinimizeBox     = $false
    $form.MaximizeBox     = $false
    $form.TopMost         = $true
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 11)
    $form.ClientSize      = New-Object System.Drawing.Size(430,190)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "CPU feature check:"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(14,14)

    $lblSSE = New-Object System.Windows.Forms.Label
    $lblSSE.AutoSize = $true
    $lblSSE.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $lblSSE.Location = New-Object System.Drawing.Point(14,48)
    $lblSSE.Text = "SSE4.2 : " + ($(if($HasSSE42){"SUPPORTED"} else {"NOT SUPPORTED"}))
    $lblSSE.ForeColor = if ($HasSSE42) { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::Firebrick }

    $lblPOPCNT = New-Object System.Windows.Forms.Label
    $lblPOPCNT.AutoSize = $true
    $lblPOPCNT.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $lblPOPCNT.Location = New-Object System.Drawing.Point(14,76)
    $lblPOPCNT.Text = "POPCNT : " + ($(if($HasPOPCNT){"SUPPORTED"} else {"NOT SUPPORTED"}))
    $lblPOPCNT.ForeColor = if ($HasPOPCNT) { [System.Drawing.Color]::ForestGreen } else { [System.Drawing.Color]::Firebrick }

    $question = New-Object System.Windows.Forms.Label
    $question.AutoSize = $true
    $question.Location = New-Object System.Drawing.Point(14,112)
    $question.Text = "Do you want to continue?"

    $btnYes = New-Object System.Windows.Forms.Button
    $btnYes.Text = "Yes"
    $btnYes.Size = New-Object System.Drawing.Size(100,34)
    $btnYes.Location = New-Object System.Drawing.Point(200,140)
    $btnYes.Add_Click({ $form.DialogResult = [System.Windows.Forms.DialogResult]::Yes; $form.Close() })

    $btnNo = New-Object System.Windows.Forms.Button
    $btnNo.Text = "No"
    $btnNo.Size = New-Object System.Drawing.Size(100,34)
    $btnNo.Location = New-Object System.Drawing.Point(310,140)
    $btnNo.Add_Click({ $form.DialogResult = [System.Windows.Forms.DialogResult]::No; $form.Close() })

    $form.AcceptButton = $btnYes
    $form.CancelButton = $btnNo

    $form.Controls.AddRange(@($title,$lblSSE,$lblPOPCNT,$question,$btnYes,$btnNo))
    return $form.ShowDialog()
}


try {
    # ---- Intro ----
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
    $grid.Dock = 'Fill'; $grid.RowCount = 3; $grid.ColumnCount = 2
    $grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,80)))
    $grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,20)))
    $grid.AutoSize = $true

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Tips2Fix - Windows 11 25H2 Installer"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(255,140,0)
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

    $leftSpacer = New-Object System.Windows.Forms.Label
    $leftSpacer.Text = ""; $leftSpacer.AutoSize = $true
    $grid.Controls.Add($leftSpacer, 0, 2)

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = "Continue"
    $btn.Width = 140; $btn.Height = 40
    $btn.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btn.Anchor = 'Right'
    $btn.Margin = New-Object System.Windows.Forms.Padding(6)
    $grid.Controls.Add($btn, 1, 2)

    if ($AutoContinue) {
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1000
        $sec = 5
        $countLbl = New-Object System.Windows.Forms.Label
        $countLbl.Text = "Auto-continue in $sec..."
        $countLbl.AutoSize = $true
        $grid.Controls.Add($countLbl, 0, 2)
        $timer.Add_Tick({
            $script:sec -= 1
            if ($script:sec -le 0) {
                $timer.Stop()
                $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
                $form.Close()
            } else {
                $countLbl.Text = "Auto-continue in $script:sec..."
            }
        })
        $timer.Start()
    }

    $form.Controls.Add($grid)
    $form.AcceptButton = $btn
    $form.Topmost = $true
    $res = $form.ShowDialog()
    if ($res -ne [System.Windows.Forms.DialogResult]::OK) { throw "User cancelled at intro." }
    Log "Intro accepted."

    # ---- CPU feature check (POPCNT & SSE4.2) with styled dialog ----
    $features = Get-CPUFeatures
    if ($features -ne $null) {
        Log ("CPU features: SSE4.2={0} POPCNT={1}" -f $features.SSE42, $features.POPCNT)
        $resp = Show-CPUCheckDialog -HasSSE42:$features.SSE42 -HasPOPCNT:$features.POPCNT
        if ($resp -ne [System.Windows.Forms.DialogResult]::Yes) {
            throw "User cancelled after CPU feature check."
        }
    } else {
        Log "CPU feature check skipped (session is not x64)."
    }

    # ---- Mode selection (bigger font, no extra-args) ----
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
    $modeRes = $modeForm.ShowDialog()
    if ($modeRes -ne [System.Windows.Forms.DialogResult]::OK) { throw "User cancelled at mode selection." }

    $selectedMode = if ($rb2.Checked) { "advanced" } elseif ($rb3.Checked) { "reset" } else { "fast" }
    Log "Mode: $selectedMode"

    # ---- ISO picker ----
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

    # ---- Mount ISO (robust, with wait) ----
    Log "Mounting ISO..."
    $disk = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop

    $drive = $null
    for ($i = 0; $i -lt 60; $i++) {
        try {
            $disk = Get-DiskImage -ImagePath $isoPath -ErrorAction Stop
            if ($disk.Attached) {
                $vol = Get-Volume -DiskImage $disk -ErrorAction SilentlyContinue | Where-Object DriveLetter
                if ($vol -and $vol.DriveLetter) {
                    $drive = "$($vol.DriveLetter):"
                    if (Test-Path "$drive\") { break }
                }
            }
        } catch { }
        Start-Sleep -Seconds 1
    }
    if (-not $drive -or -not (Test-Path "$drive\")) {
        throw "ISO mount did not expose a drive letter in time. Attached=$($disk.Attached)."
    }
    Log "Mounted at $drive"

    # ---- Progress UI ----
    $progForm = New-Object System.Windows.Forms.Form
    $progForm.Text = "Extracting files..."
    $progForm.Width = 560; $progForm.Height = 170; $progForm.StartPosition = "CenterScreen"
    $progForm.Font  = New-Object System.Drawing.Font("Segoe UI", 11)

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Location = New-Object System.Drawing.Point(10,20); $bar.Width = 520
    $bar.Minimum = 0; $bar.Maximum = 100
    $progForm.Controls.Add($bar)

    $lblProg = New-Object System.Windows.Forms.Label
    $lblProg.Location = New-Object System.Drawing.Point(10,60); $lblProg.AutoSize = $true; $lblProg.Text = "Preparing..."
    $progForm.Controls.Add($lblProg)
    $progForm.Topmost = $true; $progForm.Show()

    $totalFiles = (Get-ChildItem -Path "$drive\" -Recurse -Force | Where-Object { -not $_.PSIsContainer }).Count
    if ($totalFiles -eq 0) { $totalFiles = 1 }

    # Readiness wait: require setup.exe and stable file count (3 checks)
    $stableReads = 0
    $prevCount   = -1
    for ($i = 0; $i -lt 60 -and $stableReads -lt 3; $i++) {
        try {
            if (Test-Path "$drive\sources\setup.exe") {
                $count = (Get-ChildItem -Path "$drive\" -Recurse -Force -ErrorAction Stop |
                          Where-Object { -not $_.PSIsContainer }).Count
                if ($count -eq $prevCount) { $stableReads++ } else { $stableReads = 0; $prevCount = $count }
            }
        } catch { $stableReads = 0 }
        Start-Sleep -Milliseconds 500
    }

    # Warm-up: touch the root to ensure readability
    for ($warm = 1; $warm -le 10; $warm++) {
        try {
            if (Test-Path "$drive\" -PathType Container) {
                Get-ChildItem -Path "$drive\" -ErrorAction Stop | Out-Null
                break
            }
        } catch { }
        Start-Sleep -Milliseconds 300
    }

    # ---- Robocopy with one retry before fallback (friendly wording) ----
    $maxTries = 2
    $rc = 99
    $usedFallback = $false

    for ($try = 1; $try -le $maxTries; $try++) {
        if (-not $QuietCopyLogs) { Log "Robocopy attempt $try of $maxTries..." }
        $lblProg.Text = "Extracting... (preparing files)"
        $robArgs = @("`"$drive\`"","`"$dest\`"","/MIR","/R:2","/W:2","/NFL","/NDL","/NJH","/NJS")
        $proc = Start-Process -FilePath "robocopy.exe" -ArgumentList $robArgs -PassThru -WindowStyle Hidden

        while (-not $proc.HasExited) {
            $done = (Get-ChildItem -Path $dest -Recurse -Force | Where-Object { -not $_.PSIsContainer }).Count
            $percent = [Math]::Min(100,[Math]::Round(($done/$totalFiles)*100))
            $bar.Value = $percent
            $lblProg.Text = "Extracting... $percent% complete"
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 500
        }

        $rc = $proc.ExitCode
        if ($rc -le 7) {
            if (-not $QuietCopyLogs) { Log "Robocopy completed (code $rc)." }
            break
        } else {
            if (-not $QuietCopyLogs) { Log "Robocopy reported code $rc; will retry if needed." }
            if ($try -lt $maxTries) { Start-Sleep -Seconds 2 }
        }
    }

    if ($rc -gt 7) {
        $usedFallback = $true
        $lblProg.Text = "Extracting (direct copy)..."
        Log "Switching method: using direct Copy-Item..."
        Copy-Item -Path "$drive\*" -Destination $dest -Recurse -Force -ErrorAction Stop
    }

    $progForm.Close()

    # Dismount ISO now
    try { Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue } catch {}

    # Verify setup files exist
    $sourcesPath = Join-Path $dest "sources"
    $setupPrep = Join-Path $sourcesPath "setupprep.exe"
    $setupExe  = Join-Path $sourcesPath "setup.exe"
    if (-not (Test-Path $setupPrep) -and -not (Test-Path $setupExe)) {
        throw "Extraction incomplete. 'sources' folder or setup files not found at: $sourcesPath"
    }

    if ($usedFallback) {
        Log "Copy finished successfully via direct copy to $dest"
    } else {
        Log "Copy finished successfully via Robocopy to $dest"
    }

    # ---- Registry helpers ----
    function Apply-Bypass {
        Log "Applying bypass keys..."
        New-Item -Path "HKLM:\SYSTEM\Setup\LabConfig" -Force | Out-Null
        Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassTPMCheck"        -Value 1 -Type DWord
        Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassSecureBootCheck" -Value 1 -Type DWord
        Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassRAMCheck"        -Value 1 -Type DWord
        Set-ItemProperty "HKLM:\SYSTEM\Setup\LabConfig" -Name "BypassCPUCheck"        -Value 1 -Type DWord
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
        "reset"    { Reset-Bypass; [System.Windows.Forms.MessageBox]::Show("Registry reset completed.","Tips2Fix",[System.Windows.Forms.MessageBoxButtons]::OK) | Out-Null; exit }
        default    { }
    }

    # ---- Launch Windows Setup (non-blocking), then 5s later show message + open subscribe in NEW browser window ----
    if (Test-Path $setupPrep) { $exe = $setupPrep } else { $exe = $setupExe }
    $args = "/product server"     # <— extraArgs removed intentionally

    Log "Launching: $exe $args"
    Start-Process -FilePath $exe -ArgumentList $args -Verb RunAs  # do NOT wait

    Start-Sleep -Seconds 5  # give Setup time to appear

    [System.Windows.Forms.MessageBox]::Show(
        ("Enjoy Windows 11 25H2!" + [Environment]::NewLine +
         "Thanks for using Tips2Fix." + [Environment]::NewLine +
         "A new browser window with Tips2Fix YouTube will pop up. Please click Subscribe on the confirmation dialog." + [Environment]::NewLine +
         "Thank you for subscribing - God loves you and may God bless you!"),
        "Done - Tips2Fix",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    try {
        Open-Url-NewWindow -Url $SubscribeUrl
        Log "Opened subscribe link in a new browser window."
    } catch {
        Log "Could not open browser: $_"
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
    } catch { Write-Host "Could not show message box: $_" }
}
finally {
    Read-Host "Script finished. Press Enter to close this window..."
}
