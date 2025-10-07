<# 
Tips2Fix
Windows 11 25H2 Quick Installer v1.0.3 (Safe Confirmed Edition)
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

# ===== CPU features (heuristic, AV-friendly) helpers =====
function Get-CpuNames {
    try { (Get-CimInstance Win32_Processor -ErrorAction Stop).Name | ForEach-Object { $_.Trim() } } catch { @() }
}
function Infer-FeaturesFromCpuName {
    param([Parameter(Mandatory)][string]$Name)
    $sse42=$null; $popcnt=$null

    if ($Name -match 'Intel') {
        if ($Name -match 'Core 2|Pentium D|Pentium\(R\) Dual') { $sse42=$false; $popcnt=$false }
        elseif ($Name -match 'Core\(TM\) i[3579]|Xeon|W-|E3-|E5-|E7-|Silver|Gold|Platinum') { $sse42=$true; $popcnt=$true }
    } elseif ($Name -match 'AMD') {
        if ($Name -match 'Ryzen|EPYC|Threadripper|FX|Bulldozer|Piledriver|Steamroller|Excavator') { $sse42=$true; $popcnt=$true }
        elseif ($Name -match 'Phenom II|Athlon II|Opteron 23|Opteron 24') { $sse42=$false; $popcnt=$true }
    }

    [pscustomobject]@{ Name=$Name; SSE42=$sse42; POPCNT=$popcnt }
}
function To-FeatText($b) { if ($b -eq $true) {'SUPPORTED'} elseif ($b -eq $false) {'NOT SUPPORTED'} else {'UNKNOWN'} }

# Themed dialog (AV-safe heuristic UI)
function Show-CPUHeuristicDialog {
    param([Parameter(Mandatory)]$Results)

    # Fallback for To-FeatText if not already defined
    if (-not (Get-Command To-FeatText -ErrorAction SilentlyContinue)) {
        function To-FeatText($b) { if ($b -eq $true) {'SUPPORTED'} elseif ($b -eq $false) {'NOT SUPPORTED'} else {'UNKNOWN'} }
    }

    $allSse42  = (($Results | Where-Object { $_.SSE42  -eq $true }).Count  -eq $Results.Count)
    $allPopcnt = (($Results | Where-Object { $_.POPCNT -eq $true }).Count -eq $Results.Count)
    $anyUnknown = [bool]($Results | Where-Object { $_.SSE42 -eq $null -or $_.POPCNT -eq $null })

    # --- Base form
    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "CPU Features (Heuristic)"
    $form.StartPosition   = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MinimizeBox     = $false
    $form.MaximizeBox     = $false
    $form.TopMost         = $true
    $form.AutoScaleMode   = 'Dpi'
    $form.Font            = New-Object System.Drawing.Font("Segoe UI", 11)
    $form.ClientSize      = New-Object System.Drawing.Size(600, 420)

    # Bottom bar so OK never scrolls away
    $bottomPanel = New-Object System.Windows.Forms.Panel
    $bottomPanel.Dock    = 'Bottom'
    $bottomPanel.Height  = 56
    $bottomPanel.Padding = New-Object System.Windows.Forms.Padding(0,6,10,6)
    $form.Controls.Add($bottomPanel)

    $btnFlow = New-Object System.Windows.Forms.FlowLayoutPanel
    $btnFlow.Dock          = 'Right'
    $btnFlow.FlowDirection = 'RightToLeft'
    $btnFlow.AutoSize      = $true
    $btnFlow.Margin        = New-Object System.Windows.Forms.Padding(0)
    $bottomPanel.Controls.Add($btnFlow)

    # Scrollable content root
    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock        = 'Fill'
    $root.AutoSize    = $true
    $root.AutoScroll  = $true
    $root.ColumnCount = 1
    $root.Padding     = New-Object System.Windows.Forms.Padding(8)
    $form.Controls.Add($root)

    # Title
    $title = New-Object System.Windows.Forms.Label
    $title.Text = "CPU features (Heuristic Method)"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(255,140,0)
    $title.AutoSize = $true
    $title.Margin   = New-Object System.Windows.Forms.Padding(0,0,0,2)
    $root.Controls.Add($title)

    # Summary
    $summary = New-Object System.Windows.Forms.Label
    $summary.AutoSize = $true
    $summary.Margin   = New-Object System.Windows.Forms.Padding(0,2,0,6)
    $summary.Font     = New-Object System.Drawing.Font("Segoe UI", 11)
    $summary.Text     = "Summary (all sockets):  SSE4.2: " + (To-FeatText($(if ($anyUnknown) {$null} else {$allSse42}))) +
                        "   |   POPCNT: " + (To-FeatText($(if ($anyUnknown) {$null} else {$allPopcnt})))
    $root.Controls.Add($summary)

    # Per-CPU details
    $list = New-Object System.Windows.Forms.TableLayoutPanel
    $list.AutoSize    = $true
    $list.ColumnCount = 1
    $list.Dock        = 'Top'
    $list.Margin      = New-Object System.Windows.Forms.Padding(0,0,0,6)
    $root.Controls.Add($list)

    $featFont = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
    $bullet   = [char]0x2022

    foreach ($r in $Results) {
        $grp = New-Object System.Windows.Forms.Panel
        $grp.AutoSize = $true
        $grp.Padding  = New-Object System.Windows.Forms.Padding(6,6,6,6)
        $grp.Margin   = New-Object System.Windows.Forms.Padding(0,2,0,2)

        $name = New-Object System.Windows.Forms.Label
        $name.Text = "$bullet $($r.Name)"
        $name.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
        $name.AutoSize = $true
        $grp.Controls.Add($name)

        $lblSSE = New-Object System.Windows.Forms.Label
        $lblSSE.AutoSize  = $true
        $lblSSE.Top       = $name.Bottom + 4
        $lblSSE.Left      = 20
        $lblSSE.Text      = "SSE4.2 : " + (To-FeatText $r.SSE42)
        $lblSSE.Font      = $featFont
        $lblSSE.ForeColor = if ($r.SSE42 -eq $true) { [System.Drawing.Color]::ForestGreen } elseif ($r.SSE42 -eq $false) { [System.Drawing.Color]::Firebrick } else { [System.Drawing.Color]::DimGray }
        $grp.Controls.Add($lblSSE)

        $lblPOP = New-Object System.Windows.Forms.Label
        $lblPOP.AutoSize  = $true
        $lblPOP.Top       = $lblSSE.Bottom + 4
        $lblPOP.Left      = 20
        $lblPOP.Text      = "POPCNT : " + (To-FeatText $r.POPCNT)
        $lblPOP.Font      = $featFont
        $lblPOP.ForeColor = if ($r.POPCNT -eq $true) { [System.Drawing.Color]::ForestGreen } elseif ($r.POPCNT -eq $false) { [System.Drawing.Color]::Firebrick } else { [System.Drawing.Color]::DimGray }
        $grp.Controls.Add($lblPOP)

        $list.Controls.Add($grp)
    }

    # Note + links + tip (wrapped to avoid right-side empty space)
    $notePanel = New-Object System.Windows.Forms.TableLayoutPanel
    $notePanel.AutoSize    = $true
    $notePanel.ColumnCount = 1
    $notePanel.Dock        = 'Top'
    $notePanel.Padding     = New-Object System.Windows.Forms.Padding(2,6,2,6)
    $root.Controls.Add($notePanel)

    $noteLbl = New-Object System.Windows.Forms.Label
    $noteLbl.AutoSize     = $true
    $noteLbl.Font         = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
    $noteLbl.ForeColor    = [System.Drawing.Color]::DimGray
    $noteLbl.MaximumSize  = New-Object System.Drawing.Size(560, 0)   # wrap here
    $noteLbl.Text         = "Note: This is a quick heuristic check for SSE4.2 and POPCNT.`r`n" +
                            "If results look wrong or you're not 100% sure, use one of these advanced methods:"
    $notePanel.Controls.Add($noteLbl)

    $linkCpuZ = New-Object System.Windows.Forms.LinkLabel
    $linkCpuZ.Text            = "- Download CPU-Z (official)"
    $linkCpuZ.AutoSize        = $true
    $linkCpuZ.LinkColor       = [System.Drawing.Color]::FromArgb(0,102,204)
    $linkCpuZ.ActiveLinkColor = [System.Drawing.Color]::FromArgb(0,102,204)
    $linkCpuZ.Margin          = New-Object System.Windows.Forms.Padding(0,4,0,2)
    $linkCpuZ.UseMnemonic     = $false
    $linkCpuZ.Add_LinkClicked({
        try { Start-Process "https://www.cpuid.com/softwares/cpu-z.html" | Out-Null } catch {}
        if (Get-Command Log -ErrorAction SilentlyContinue) { Log "Opened CPU-Z site." }
    })
    $notePanel.Controls.Add($linkCpuZ)

    $linkCoreinfo = New-Object System.Windows.Forms.LinkLabel
    $linkCoreinfo.Text            = "- Download Coreinfo (Sysinternals)"
    $linkCoreinfo.AutoSize        = $true
    $linkCoreinfo.LinkColor       = [System.Drawing.Color]::FromArgb(0,102,204)
    $linkCoreinfo.ActiveLinkColor = [System.Drawing.Color]::FromArgb(0,102,204)
    $linkCoreinfo.UseMnemonic     = $false
    $linkCoreinfo.Margin          = New-Object System.Windows.Forms.Padding(0,0,0,4)
    $linkCoreinfo.Add_LinkClicked({
        try { Start-Process "https://learn.microsoft.com/sysinternals/downloads/coreinfo" | Out-Null } catch {}
        if (Get-Command Log -ErrorAction SilentlyContinue) { Log "Opened Coreinfo page." }
    })
    $notePanel.Controls.Add($linkCoreinfo)

# NEW: blog post (how to use this advanced method cpuz and pcoreinfo)
$linkBlog = New-Object System.Windows.Forms.LinkLabel
$linkBlog.Text            = "- See step-by-step guide: Tips2Fix blog post"
$linkBlog.AutoSize        = $true
$linkBlog.LinkColor       = [System.Drawing.Color]::FromArgb(0,102,204)
$linkBlog.ActiveLinkColor = [System.Drawing.Color]::FromArgb(0,102,204)
$linkBlog.Margin          = New-Object System.Windows.Forms.Padding(0,6,0,0)
$linkBlog.UseMnemonic     = $false
$linkBlog.Add_LinkClicked({
    try { Start-Process "https://tips2fix.com/how-to-check-if-your-pc-supports-sse4-2-and-popcnt-easy-methods/" | Out-Null } catch {}
    if (Get-Command Log -ErrorAction SilentlyContinue) { Log "Opened Tips2Fix blog post." }
})
$notePanel.Controls.Add($linkBlog)

    # Buttons
    $script:openCoreinfo = $false

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text   = if ($anyUnknown) { "Close" } else { "OK" }
    $btnClose.Width  = 110
    $btnClose.Height = 36
    $btnClose.Add_Click({ $form.Close() })
    $btnFlow.Controls.Add($btnClose)

    if ($anyUnknown) {
        $btnCore = New-Object System.Windows.Forms.Button
        $btnCore.Text   = "Open Coreinfo"
        $btnCore.Width  = 140
        $btnCore.Height = 36
        $btnCore.Margin = New-Object System.Windows.Forms.Padding(6,0,0,0)
        $btnCore.Add_Click({ $script:openCoreinfo = $true; $form.Close() })
        $btnFlow.Controls.Add($btnCore)
    }

    $form.AcceptButton = $btnClose
    $form.ShowDialog() | Out-Null
    return $script:openCoreinfo
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

# --- Console disclaimer banner ---
Write-Host ""
Write-Host "DISCLAIMER" -ForegroundColor Yellow
Write-Host "This tool helps you install/upgrade Windows 11 25H2." -ForegroundColor Gray
Write-Host "Proceeding may modify your system and is done at your own risk." -ForegroundColor Gray
Write-Host "Always make a full backup before continuing." -ForegroundColor Gray
Write-Host "Please read the popup and click 'Continue' to confirm you understand." -ForegroundColor Cyan
Write-Host ""



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
    $grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,80))) | Out-Null
    $grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,20))) | Out-Null
    $grid.AutoSize = $true

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Tips2Fix - Windows 11 25H2 Installer"
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(255,140,0)  # ORANGE (original)
    $title.AutoSize = $true
    $title.Margin   = New-Object System.Windows.Forms.Padding(6,6,6,2)
    $grid.Controls.Add($title, 0, 0)
    $grid.SetColumnSpan($title, 2)

    # Subtitle under the orange title
$sub = New-Object System.Windows.Forms.Label
$sub.Text = "Backup your files first! Installing on unsupported hardware is risky." +
            "`r`nBy clicking Continue you confirm you have read and accept this disclaimer."
$sub.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$sub.AutoSize = $true
$sub.Margin   = New-Object System.Windows.Forms.Padding(6,0,6,4)
$grid.Controls.Add($sub, 0, 1)
$grid.SetColumnSpan($sub, 2)

# Small gray disclaimer text (1–2 lines, unobtrusive)


$disc = New-Object System.Windows.Forms.Label
$disc.Text = "This process may change system settings and perform an in-place setup. " +
             "`r`nYou are responsible for your data and system state."
$disc.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$disc.ForeColor = [System.Drawing.Color]::DimGray
$disc.AutoSize = $true
$disc.Margin   = New-Object System.Windows.Forms.Padding(6,0,6,10)
$grid.Controls.Add($disc, 0, 2)
$grid.SetColumnSpan($disc, 2)
$grid.RowStyles.Clear()
$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize'))) | Out-Null         # row 0: title
$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))  | Out-Null        # row 1: subtitle
$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100))) | Out-Null     # row 2: spacer/filler
$grid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))  | Out-Null        # row 3: buttons

# --- Bottom-right button panel ---
$btnPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$btnPanel.FlowDirection = 'RightToLeft'
$btnPanel.Dock          = 'Fill'
$btnPanel.AutoSize      = $true
$btnPanel.Padding       = New-Object System.Windows.Forms.Padding(0,6,6,6)

$btn = New-Object System.Windows.Forms.Button
$btn.Text   = "Continue"
$btn.AutoSize = $true
$btn.Padding  = New-Object System.Windows.Forms.Padding(18,8,18,8)
$btn.DialogResult = [System.Windows.Forms.DialogResult]::OK

$btnPanel.Controls.Add($btn)

# vendose panelin e butonit në rreshtin 3 dhe zgjeroje te 2 kolonat
$grid.Controls.Add($btnPanel, 0, 3)
$grid.SetColumnSpan($btnPanel, 2)

$form.Controls.Add($grid)
$form.AcceptButton = $btn
$form.Topmost = $true
if ($form.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw "User cancelled at intro." }
Log "Intro accepted."



# ===== CPU features (heuristic) — auto & themed =====

# --- console hint (tiny, safe) ---
Write-Host ""
Write-Host "Checking CPU features (SSE4.2 / POPCNT)..." -ForegroundColor Cyan


$cpuNames = Get-CpuNames
if (-not $cpuNames -or $cpuNames.Count -eq 0) { $cpuNames = @("(unknown CPU)") }

$results = $cpuNames | ForEach-Object { Infer-FeaturesFromCpuName -Name $_ }

# Shfaq dialogun me ngjyra; nëse ka UNKNOWN i ofro user-it Coreinfo
$openCoreinfo = Show-CPUHeuristicDialog -Results $results
if ($openCoreinfo) {
    try {
        Start-Process "https://learn.microsoft.com/sysinternals/downloads/coreinfo" | Out-Null
        Log "Opened Coreinfo page."
    } catch { Log "Failed to open Coreinfo page: $_" }
}

# Log per audit
Log ("CPU heuristic: " + ($results | ForEach-Object {
    "[{0}] SSE4.2={1} POPCNT={2}" -f $_.Name,(To-FeatText $_.SSE42),(To-FeatText $_.POPCNT)
} | Out-String).Trim())



# --- tiny console summary (no new helpers) ---
$sse42All  = (($results | Where-Object { $_.SSE42  -eq $true }).Count  -eq $results.Count)
$popcntAll = (($results | Where-Object { $_.POPCNT -eq $true }).Count -eq $results.Count)
$anyUnknown = ($results | Where-Object { $_.SSE42 -eq $null -or $_.POPCNT -eq $null }).Count -gt 0

if ($anyUnknown) {
    Write-Host "Summary: some features are UNKNOWN (see popup for details)." -ForegroundColor DarkYellow
} else {
    Write-Host ("Summary: SSE4.2={0} | POPCNT={1}" -f (To-FeatText $sse42All),(To-FeatText $popcntAll)) -ForegroundColor DarkCyan
}

Write-Host "CPU feature check complete." -ForegroundColor DarkCyan


# ===== /CPU features =====


# --- console hint before mode popup ---
Write-Host ""
Write-Host "Select one of the installation modes in the popup, then click OK:" -ForegroundColor Cyan
Write-Host "  1) Fast install / upgrade (no registry edits)"
Write-Host "  2) Advanced install (apply bypass registry keys)"
Write-Host "  3) Reset registry keys to original (remove bypass)"

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
   

Write-Host ("Mode selected: {0}" -f $selectedMode) -ForegroundColor DarkCyan




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

# --- console hint before ISO file picker ---
Write-Host ""
Write-Host "Now select your Downloaded Windows 11 25H2 ISO file ..." -ForegroundColor Cyan


    # ===== ISO picker =====
    
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = "ISO files (*.iso)|*.iso"
    $ofd.Title  = "Select Windows 11 25H2 ISO"
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host "ISO selection was cancelled." -ForegroundColor Yellow
    throw "User cancelled ISO picker."}
    $isoPath = $ofd.FileName
    $isoName = [System.IO.Path]::GetFileNameWithoutExtension($isoPath)
    $dest    = Join-Path $desktop $isoName
    if (-not (Test-Path $dest)) { New-Item -Path $dest -ItemType Directory | Out-Null }
    Log "ISO selected: $isoPath"
    Log "Destination: $dest"


Write-Host ("ISO chosen: {0}" -f $isoPath) -ForegroundColor DarkCyan
Write-Host ("Destination folder: {0}" -f $dest) -ForegroundColor DarkCyan


# After:
# $isoPath = $ofd.FileName
# $isoName = [System.IO.Path]::GetFileNameWithoutExtension($isoPath)
# $dest    = Join-Path $desktop $isoName

# --- console hint before extraction confirm ---
Write-Host ""
Write-Host "Please confirm extraction..." -ForegroundColor Cyan
Write-Host ("  ISO selected : {0}" -f $isoPath) -ForegroundColor DarkCyan
Write-Host ("  Destination  : {0}" -f $dest)    -ForegroundColor DarkCyan
Write-Host ("  A folder named '{0}' will be created and the ISO contents will be extracted there." -f $isoName) -ForegroundColor DarkCyan
Write-Host "Waiting for your confirmation in the popup..." -ForegroundColor Yellow



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

# --- console hint before launching Setup ---
Write-Host ""
Write-Host "Everything looks ready for Windows 11 Setup." -ForegroundColor Cyan
Write-Host ("Setup executable : {0}" -f $setup) -ForegroundColor DarkCyan
Write-Host "It will start as soon as you confirm in the popup..." -ForegroundColor Yellow
Write-Host "Waiting for your confirmation..." -ForegroundColor Yellow

# We already validated $setup above, so no need to re-detect here.
$confirmSetup = [System.Windows.Forms.MessageBox]::Show(
    "Do you want to start Windows 11 Setup now?",
    "Confirm Setup",
    [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Question
)

if ($confirmSetup -eq [System.Windows.Forms.DialogResult]::Yes) {
    Write-Host "Starting Windows 11 Setup..." -ForegroundColor Green
    Log "Launching setup: $setup /product server"
    Start-Process -FilePath $setup -ArgumentList "/product server" -Verb RunAs

    # Console-only cleanup note
    Write-Host ""
    Write-Host "When the installation is completely finished, you can safely delete the extracted folder:" -ForegroundColor Yellow
    Write-Host "  $dest"
    Log "Cleanup note shown for: $dest"

    # Single dialog: success + subscribe

    
    $msg = @"
Installation started successfully.
Enjoy Windows 11 25H2.
Would you like to open the Tips2Fix YouTube channel and subscribe?
"@

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
else {
    Write-Host "Setup launch cancelled by the user." -ForegroundColor Yellow
    Log "User cancelled setup launch."
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


