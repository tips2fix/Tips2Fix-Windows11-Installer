<#
Tips2Fix
Windows 11 26H2 Quick Installer v1.2.0 (Safe Confirmed Edition)
All-in-one PowerShell script (PS 5.1 compatible)
https://github.com/tips2fix/Tips2Fix-Windows11-Installer

Design notes: Segoe UI and Segoe MDL2 Assets are used throughout because both ship
with Windows 10 and Windows 11. Segoe Fluent Icons and Segoe UI Variable are
Windows 11 only and would fall back to something ugly for Windows 10 users.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ErrorActionPreference = 'Stop'

# ===================== Constants =====================

$AppVersion    = '1.2.0'
$TargetName    = '26H2'
$TargetBuild   = 26300
$EkbKb         = 'KB5121794'
$EkbPrereqKb   = 'KB5120998'
$EkbCatalogUrl = 'https://www.catalog.update.microsoft.com/Search.aspx?q=KB5121794'
$EkbEligible   = @(26100, 26200)
$IsoDownloadUrl= 'https://www.microsoft.com/software-download/windows11'

# Direct .msu links from Microsoft's Delivery Optimization server. They point at one
# exact build, so the Update Catalog page is offered alongside them as a fallback.
$EkbDirectX64   = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/94520a88-858f-4832-a57d-7211f6d84a4e/public/Windows11.0-KB5121794-x64_5e20a3cce48d6611b16bdec42b07167f5456586a.msu'
$EkbDirectArm64 = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/9d8dc3d0-9cbf-4eb1-9411-722e3e6a19b3/public/Windows11.0-KB5121794-arm64_77a76caf2d362bb293a4d18058388f2717365abe.msu'
$EkbPrereqUrl   = 'https://www.catalog.update.microsoft.com/Search.aspx?q=KB5120998'

# Direct x64 link for the prerequisite. It is a full cumulative update, so it is
# roughly 4.3 GB, not a small package. No direct ARM64 link is published, so ARM
# machines are sent to the catalog instead.
$EkbPrereqX64   = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/7416ff4e-4741-42fb-a16b-0a92e2dfc42b/public/windows11.0-kb5120998-x64_5cdebefaecf780c7487e56a0d5472830a24a673a.msu'

# KB5120998 produces builds 26100.9278 and 26200.9278, so the UBR is the test.
$EkbPrereqUbr   = 9278
$SubscribeUrl  = 'https://www.youtube.com/channel/UC3kEO7SEulVV__uGbbumQog?sub_confirmation=1'
$BlogSse42Url  = 'https://tips2fix.com/how-to-check-if-your-pc-supports-sse4-2-and-popcnt-easy-methods/'
$PcHealthUrl        = 'https://aka.ms/GetPCHealthCheckApp'
$PcHealthSupportUrl = 'https://support.microsoft.com/en-us/windows/experience/compatibility/how-to-use-the-pc-health-check-app'
$CpuZUrl       = 'https://www.cpuid.com/softwares/cpu-z.html'
$CoreinfoUrl   = 'https://learn.microsoft.com/sysinternals/downloads/coreinfo'

$LabConfigPath = 'HKLM:\SYSTEM\Setup\LabConfig'
$MoSetupPath   = 'HKLM:\SYSTEM\Setup\MoSetup'
$HwReqChkPath  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\HwReqChk'
$PchcPath      = 'HKCU:\Software\Microsoft\PCHC'
$LabConfigValues = @('BypassTPMCheck','BypassSecureBootCheck','BypassRAMCheck','BypassCPUCheck','BypassStorageCheck','BypassDiskCheck')

# A failed earlier attempt caches an "incompatible" verdict that blocks later retries.
$CompatStalePaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\CompatMarkers'
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Shared'
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\TargetVersionUpgradeExperienceIndicators'
)

$UpgradeFreeSpaceBytes = 25GB

# Standalone patcher shipped next to this script. The GUI runs it when present so
# there is a single implementation; if it is missing, the built-in functions below
# do exactly the same thing.
$BypassCmdName = 'Bypass-Requirements.cmd'

# The "system reserved partition" error is the EFI System Partition running out of
# room, almost always old boot fonts. This is the folder Setup needs cleared.
$EfiMountLetter = 'Y'
$EfiFontsRel    = 'EFI\Microsoft\Boot\Fonts'

$EditionIdMap = @{
    'Core'                    = 'Home'
    'CoreN'                   = 'Home N'
    'CoreSingleLanguage'      = 'Home Single Language'
    'Professional'            = 'Pro'
    'ProfessionalN'           = 'Pro N'
    'ProfessionalEducation'   = 'Pro Education'
    'ProfessionalWorkstation' = 'Pro for Workstations'
    'Enterprise'              = 'Enterprise'
    'EnterpriseN'             = 'Enterprise N'
    'Education'               = 'Education'
    'EducationN'              = 'Education N'
}

$desktop     = [Environment]::GetFolderPath('Desktop')
$LogKeep     = 20      # newest log files kept; older ones are removed
$logPath     = $null   # set by Initialize-T2FLog when the tool starts
$scriptStart = Get-Date

$script:MountedIsoPath = $null
$script:SetupProc      = $null

function Log {
    param([string]$msg)
    $t = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    if ($logPath) {
        try { "[$t] $msg" | Out-File -FilePath $logPath -Append -Encoding UTF8 } catch {}
    }
    Write-Host "[$t] $msg"
}

# Creates this run's own log file and returns its path (or $null if nowhere is
# writable). Every run gets a new time-stamped file, so a second test never wipes the
# first. Order: a Logs folder next to the tool, then the user's local app data, then
# TEMP. The log holds no user name or computer name.
function Initialize-T2FLog {
    param([string]$PrimaryDir, [string]$FallbackDir, [int]$Keep = 20)

    $stamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    foreach ($dir in @($PrimaryDir, $FallbackDir, (Join-Path $env:TEMP 'Tips2Fix\Logs'))) {
        if (-not $dir) { continue }
        try {
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }

            $probe = Join-Path $dir ('.write-test-' + [guid]::NewGuid().ToString('N'))
            [System.IO.File]::WriteAllText($probe, 'x')
            Remove-Item -LiteralPath $probe -Force

            $file = Join-Path $dir "Tips2Fix_$stamp.log"
            $n = 1
            while (Test-Path -LiteralPath $file) { $n++; $file = Join-Path $dir "Tips2Fix_${stamp}_$n.log" }

            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
                        ).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator')
            $header = @(
                "Tips2Fix Windows 11 $TargetName Installer v$AppVersion",
                "Started    : $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))",
                "PowerShell : $($PSVersionTable.PSVersion)",
                "Admin      : $isAdmin",
                ('-' * 60)
            )
            Set-Content -LiteralPath $file -Value $header -Encoding UTF8

            Get-ChildItem -LiteralPath $dir -Filter 'Tips2Fix_*.log' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime, Name -Descending |
                Select-Object -Skip $Keep |
                Remove-Item -Force -ErrorAction SilentlyContinue
            return $file
        } catch { continue }
    }
    return $null
}

# Reads the most recent "NN.N%" a program has printed so far, or -1 if it has not
# printed one. Works while the file is still being written.
function Get-T2FLastPercent {
    param([string]$Path)
    try {
        $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            $len = $fs.Length
            $take = [int][Math]::Min($len, 4096)
            if ($take -le 0) { return -1 }
            $null = $fs.Seek(-$take, 'End')
            $buf = New-Object byte[] $take
            $read = $fs.Read($buf, 0, $take)
            $text = [System.Text.Encoding]::ASCII.GetString($buf, 0, $read)
        } finally { $fs.Dispose() }
        $m = [regex]::Matches($text, '(\d{1,3}(?:\.\d+)?)\s*%')
        if ($m.Count -eq 0) { return -1 }
        # Explicit doubles: with plain 0 and 100, PowerShell picks the integer overload
        # and silently rounds 45.5 to 46.
        return [Math]::Min([double]100, [Math]::Max([double]0, [double]$m[$m.Count - 1].Groups[1].Value))
    } catch { return -1 }
}

# Runs a program without a window, and copies whatever it printed into the log, so a
# failure can be diagnosed later. Returns the exit code, or -1 if it could not start.
# When -OnTick is given, the program runs while the caller's window stays alive and
# the scriptblock is called about ten times a second with the percentage so far
# (-1 while unknown) and the elapsed time.
function Invoke-LoggedProcess {
    param([string]$FilePath, [string]$Arguments, [string]$Label, [scriptblock]$OnTick)

    $id  = [guid]::NewGuid().ToString('N')
    $out = Join-Path $env:TEMP "t2f_out_$id.txt"
    $err = Join-Path $env:TEMP "t2f_err_$id.txt"
    Log "Run: $Label"
    $code = -1
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru `
                -RedirectStandardOutput $out -RedirectStandardError $err
        $null = $p.Handle    # keeps the exit code readable after the process ends
        if ($OnTick) {
            $started = Get-Date; $lastRead = [datetime]::MinValue; $percent = -1
            while (-not $p.HasExited) {
                Start-Sleep -Milliseconds 90
                if (((Get-Date) - $lastRead).TotalMilliseconds -ge 350) {
                    $lastRead = Get-Date
                    $q = Get-T2FLastPercent -Path $out
                    if ($q -ge 0) { $percent = $q }
                }
                & $OnTick $percent ((Get-Date) - $started)
                [System.Windows.Forms.Application]::DoEvents()
            }
        }
        $p.WaitForExit()
        $code = [int]$p.ExitCode
    } catch {
        Log "  could not start: $($_.Exception.Message)"
    }
    foreach ($f in $out, $err) {
        try {
            # Progress bars such as "[=====   45.0%   ]" are noise in a log.
            $lines = @(Get-Content -LiteralPath $f -ErrorAction Stop |
                       Where-Object { $_.Trim() -and $_ -notmatch '^\s*\[?[=\s-]*\d{1,3}(\.\d+)?\s*%[=\s-]*\]?\s*$' })
            foreach ($line in ($lines | Select-Object -First 40)) { Log ('  | ' + $line.Trim()) }
            if ($lines.Count -gt 40) { Log "  | ... $($lines.Count - 40) more lines not shown" }
        } catch {}
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
    }
    Log "  exit code: $code"
    return $code
}

# ===================== Design system =====================

# Every text size goes through New-T2FFont, so this one number scales the whole UI.
$UiFontBump = 1.5

$UI = @{
    Window = 860   # window client width
    Card   = 780   # card width inside the body
    Inner  = 700   # content width inside a card
    Body   = 770   # full-width body text
    Dialog = 700   # Show-T2FDialog width
}

function RGB { param([int]$r,[int]$g,[int]$b) [System.Drawing.Color]::FromArgb($r,$g,$b) }

$C = @{
    Accent      = (RGB 255 140 0)
    AccentDark  = (RGB 214 108 0)
    AccentDeep  = (RGB 173 87 0)
    AccentSoft  = (RGB 255 244 230)
    Page        = (RGB 255 255 255)
    Surface     = (RGB 247 247 248)
    Border      = (RGB 228 228 231)
    Text        = (RGB 24 24 27)
    TextSoft    = (RGB 105 105 112)
    Ok          = (RGB 13 124 63)
    OkSoft      = (RGB 235 248 240)
    Warn        = (RGB 158 92 0)
    WarnSoft    = (RGB 255 247 230)
    Err         = (RGB 190 38 28)
    ErrSoft     = (RGB 254 239 238)
    White       = (RGB 255 255 255)
    Muted       = (RGB 250 250 251)
    Disabled    = (RGB 168 168 172)
    DisabledSub = (RGB 178 178 182)
}

# Segoe MDL2 Assets glyphs
$G = @{
    Check    = [char]0xE73E
    Cross    = [char]0xE711
    Warning  = [char]0xE7BA
    Info     = [char]0xE946
    Download = [char]0xE896
    Gear     = [char]0xE713
    Lock     = [char]0xE72E
}

function New-T2FFont {
    param([single]$Size = 10, [string]$Weight = 'Regular')
    $Size = $Size + $UiFontBump
    $family = switch ($Weight) {
        'Semibold' { 'Segoe UI Semibold' }
        'Light'    { 'Segoe UI Light' }
        default    { 'Segoe UI' }
    }
    $style = if ($Weight -eq 'Bold') { [System.Drawing.FontStyle]::Bold }
             elseif ($Weight -eq 'Italic') { [System.Drawing.FontStyle]::Italic }
             else { [System.Drawing.FontStyle]::Regular }
    try {
        $f = New-Object System.Drawing.Font($family, $Size, $style)
        if ($f.Name -eq $family) { return $f }
        $f.Dispose()
    } catch {}
    return (New-Object System.Drawing.Font('Segoe UI', $Size, $style))
}

function New-T2FIconFont {
    param([single]$Size = 12)
    try {
        $f = New-Object System.Drawing.Font('Segoe MDL2 Assets', $Size)
        if ($f.Name -eq 'Segoe MDL2 Assets') { return $f }
        $f.Dispose()
    } catch {}
    return (New-Object System.Drawing.Font('Segoe UI Symbol', $Size))
}

function New-RoundedPath {
    param([System.Drawing.Rectangle]$Rect, [int]$Radius)
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    if ($Rect.Width -le 0 -or $Rect.Height -le 0) { return $p }
    $d = [Math]::Min($Radius * 2, [Math]::Min($Rect.Width, $Rect.Height))
    if ($d -le 0) { $p.AddRectangle($Rect); return $p }
    $p.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
    $p.AddArc($Rect.Right - $d, $Rect.Y, $d, $d, 270, 90)
    $p.AddArc($Rect.Right - $d, $Rect.Bottom - $d, $d, $d, 0, 90)
    $p.AddArc($Rect.X, $Rect.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function New-T2FWindow {
    param([string]$Title, [string]$Subtitle = '', [int]$Width = $UI.Window, [switch]$NoAbout)

    $form = New-Object System.Windows.Forms.Form
    $form.Text            = "Tips2Fix - Windows 11 $TargetName Installer"
    $form.StartPosition   = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MinimizeBox     = $false
    $form.MaximizeBox     = $false
    $form.AutoScaleMode   = 'Dpi'
    $form.BackColor       = $C.Page
    $form.Font            = (New-T2FFont 10)
    $form.ClientSize      = New-Object System.Drawing.Size($Width, 460)

    # The focus ring only appears once the keyboard is used, like Windows itself.
    $script:KbNav = $false
    $form.KeyPreview = $true
    $form.Add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq 'Tab' -or $e.KeyCode -eq 'Left' -or $e.KeyCode -eq 'Right') {
            $script:KbNav = $true
            $s.Invalidate($true)
        }
    })

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock        = 'Fill'
    $root.ColumnCount = 1
    $root.RowCount    = 3
    $root.BackColor   = $C.Page
    $root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 104))) | Out-Null
    $root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent', 100)))  | Out-Null
    $root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute', 72)))  | Out-Null
    $form.Controls.Add($root)

    # --- Header band with the Tips2Fix gradient.
    # The title and subtitle are drawn straight onto the band instead of as two
    # transparent labels: transparent labels repaint their parent's background over
    # each other, which clipped the top of the subtitle. The height is measured from
    # the real text so nothing can overlap at any font size.
    $titleFont = New-T2FFont 19 'Semibold'
    $subFont   = New-T2FFont 10
    $textW     = $Width - 56 - 96
    $mBmp = New-Object System.Drawing.Bitmap(1, 1)
    $mGfx = [System.Drawing.Graphics]::FromImage($mBmp)
    $tH   = [int][Math]::Ceiling($mGfx.MeasureString($Title, $titleFont, $textW).Height)
    $sH   = 0
    if ($Subtitle) { $sH = [int][Math]::Ceiling($mGfx.MeasureString($Subtitle, $subFont, $textW).Height) }
    $mGfx.Dispose(); $mBmp.Dispose()

    $headerH = [Math]::Max(96, 26 + $tH + $(if ($sH -gt 0) { 8 + $sH } else { 0 }) + 26)
    $root.RowStyles[0].Height = $headerH

    $header = New-Object System.Windows.Forms.Panel
    $header.Dock   = 'Fill'
    $header.Margin = New-Object System.Windows.Forms.Padding(0)
    $header.Tag    = [pscustomobject]@{
        Title = $Title; Sub = $Subtitle; TitleFont = $titleFont; SubFont = $subFont
        TextW = $textW; TitleH = $tH; SubH = $sH
    }
    $header.Add_Paint({
        param($s, $e)
        if ($s.Width -le 0 -or $s.Height -le 0) { return }
        $gfx = $e.Graphics
        $gfx.SmoothingMode     = 'AntiAlias'
        $gfx.TextRenderingHint = 'ClearTypeGridFit'
        $t = $s.Tag

        $r = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
        $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r, $C.Accent, $C.AccentDeep, 12.0)
        $gfx.FillRectangle($br, $r)
        $br.Dispose()

        # Brand mark on the right: a soft white tile with the T2F letters.
        $tile = New-Object System.Drawing.Rectangle(($s.Width - 28 - 58), [int](($s.Height - 58) / 2), 58, 58)
        $tp   = New-RoundedPath -Rect $tile -Radius 16
        $tb   = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(48, 255, 255, 255))
        $gfx.FillPath($tb, $tp)
        $tb.Dispose(); $tp.Dispose()
        $mf = New-T2FFont 9 'Semibold'
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        $wb = New-Object System.Drawing.SolidBrush($C.White)
        $gfx.DrawString('T2F', $mf, $wb, ([System.Drawing.RectangleF]$tile), $sf)
        $sf.Dispose(); $mf.Dispose()

        $titleRect = New-Object System.Drawing.RectangleF(28, 26, $t.TextW, $t.TitleH)
        $gfx.DrawString($t.Title, $t.TitleFont, $wb, $titleRect)
        if ($t.Sub) {
            $sb = New-Object System.Drawing.SolidBrush((RGB 255 236 214))
            $subRect = New-Object System.Drawing.RectangleF(29, (26 + $t.TitleH + 8), $t.TextW, $t.SubH)
            $gfx.DrawString($t.Sub, $t.SubFont, $sb, $subRect)
            $sb.Dispose()
        }
        $wb.Dispose()
    })
    $root.Controls.Add($header, 0, 0)

    # --- Scrollable body
    $bodyHost = New-Object System.Windows.Forms.Panel
    $bodyHost.Dock       = 'Fill'
    $bodyHost.BackColor  = $C.Page
    $bodyHost.AutoScroll = $true
    $bodyHost.Padding    = New-Object System.Windows.Forms.Padding(28, 22, 28, 18)
    $bodyHost.Margin     = New-Object System.Windows.Forms.Padding(0)
    $root.Controls.Add($bodyHost, 0, 1)

    $body = New-Object System.Windows.Forms.FlowLayoutPanel
    $body.Dock          = 'Top'
    $body.FlowDirection = 'TopDown'
    $body.WrapContents  = $false
    $body.AutoSize      = $true
    $body.AutoSizeMode  = 'GrowAndShrink'
    $body.BackColor     = $C.Page
    $body.Width         = $Width - 62
    $bodyHost.Controls.Add($body)

    # --- Footer with a hairline top border
    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock      = 'Fill'
    $footer.BackColor = $C.Surface
    $footer.Margin    = New-Object System.Windows.Forms.Padding(0)
    $footer.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen($C.Border, 1)
        $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
        $pen.Dispose()
    })
    $root.Controls.Add($footer, 0, 2)

    $brand = New-Object System.Windows.Forms.Label
    $brand.Text      = "Tips2Fix  v$AppVersion"
    $brand.Font      = (New-T2FFont 8.5)
    $brand.ForeColor = $C.TextSoft
    $brand.BackColor = [System.Drawing.Color]::Transparent
    $brand.AutoSize  = $true
    $brand.Location  = New-Object System.Drawing.Point(28, 27)
    $footer.Controls.Add($brand)

    if (-not $NoAbout) {
        $about = New-Object System.Windows.Forms.LinkLabel
        $about.Text             = 'About this tool'
        $about.Font             = (New-T2FFont 8.5)
        $about.AutoSize         = $true
        $about.UseMnemonic      = $false
        $about.LinkColor        = $C.AccentDark
        $about.ActiveLinkColor  = $C.Accent
        $about.LinkBehavior     = 'HoverUnderline'
        $about.BackColor        = [System.Drawing.Color]::Transparent
        $about.Cursor           = [System.Windows.Forms.Cursors]::Hand
        $about.Location         = New-Object System.Drawing.Point(($brand.Right + 22), 27)
        $about.Add_LinkClicked({ Show-T2FAbout })
        $footer.Controls.Add($about)
    }

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock          = 'Right'
    $buttons.FlowDirection = 'RightToLeft'
    $buttons.WrapContents  = $false
    $buttons.AutoSize      = $true
    $buttons.AutoSizeMode  = 'GrowAndShrink'
    $buttons.BackColor     = $C.Surface
    $buttons.Padding       = New-Object System.Windows.Forms.Padding(0, 16, 22, 0)
    # This panel sits on top of the footer's own border, so it continues the line.
    $buttons.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen($C.Border, 1)
        $e.Graphics.DrawLine($pen, 0, 0, $s.Width, 0)
        $pen.Dispose()
    })
    $footer.Controls.Add($buttons)

    return [pscustomobject]@{
        Form    = $form
        Header  = $header
        Body    = $body
        Footer  = $footer
        Buttons = $buttons
        Width   = $Width
        HeaderHeight = $headerH
        Title   = $Title
    }
}

# Sizes the window to its content, then shows it modally.
function Show-T2FWindow {
    param($Win, [int]$MaxHeight = 0)

    $contentH = $Win.Body.PreferredSize.Height + 44
    $screenH  = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height
    $cap = if ($MaxHeight -gt 0) { $MaxHeight } else { [int]($screenH * 0.86) - $Win.HeaderHeight - 72 }
    if ($contentH -gt $cap)  { $contentH = $cap }
    if ($contentH -lt 120)   { $contentH = 120 }
    $Win.Form.ClientSize = New-Object System.Drawing.Size($Win.Width, ($Win.HeaderHeight + $contentH + 72))

    # No opacity or animation tricks here: a window that starts transparent stays
    # invisible if anything in the animation fails, and the modal window then looks
    # like a frozen script.
    # Windows can refuse to raise a new window over the console that started it, and
    # the window would only flash in the taskbar. Toggling TopMost on and straight
    # off raises it once and leaves it as an ordinary window, so it never stays on top
    # of other programs and the user can click the console or anything else freely.
    $Win.Form.Add_Shown({
        try { $this.TopMost = $true; $this.TopMost = $false; $this.Activate() } catch {}
    })

    Log "Screen: $($Win.Title)"
    $result = $Win.Form.ShowDialog()
    $Win.Form.Dispose()
    return $result
}

function New-T2FButton {
    param(
        [string]$Text,
        [ValidateSet('primary','secondary','danger','quiet')][string]$Kind = 'secondary',
        [int]$Width = 0
    )
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $Text
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::Transparent
    $b.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::Transparent
    $b.BackColor = [System.Drawing.Color]::Transparent
    $b.Font      = (New-T2FFont 10 'Semibold')
    $b.Height    = 40
    $b.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $b.Margin    = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $b.UseVisualStyleBackColor = $false

    $measured = [System.Windows.Forms.TextRenderer]::MeasureText($Text, $b.Font).Width + 46
    $b.Width = if ($Width -gt 0) { $Width } else { [Math]::Max(118, $measured) }

    $b.Tag = [pscustomobject]@{ Kind = $Kind; Hover = $false; Down = $false }

    # First handler on purpose, so the click is on record before anything it triggers.
    $b.Add_Click({ Log ('Button: ' + $this.Text) })

    $b.Add_MouseEnter({ $this.Tag.Hover = $true;  $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Tag.Hover = $false; $this.Tag.Down = $false; $this.Invalidate() })
    $b.Add_MouseDown({  $this.Tag.Down  = $true;  $this.Invalidate() })
    $b.Add_MouseUp({    $this.Tag.Down  = $false; $this.Invalidate() })

    $b.Add_Paint({
        param($s, $e)
        $gfx = $e.Graphics
        $gfx.SmoothingMode = 'AntiAlias'
        # Clearing with a transparent color paints raw white, so resolve it first.
        $bg = $s.Parent.BackColor
        if ($bg.A -eq 0) { $bg = $C.Page }
        $gfx.Clear($bg)

        $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $path = New-RoundedPath -Rect $rect -Radius 6

        $st = $s.Tag
        $fillColor = $null; $textColor = $C.Text; $borderColor = $null

        switch ($st.Kind) {
            'primary' {
                $fillColor = if ($st.Down) { $C.AccentDeep } elseif ($st.Hover) { $C.AccentDark } else { $C.Accent }
                $textColor = $C.White
            }
            'danger' {
                $fillColor = if ($st.Down) { (RGB 150 28 20) } elseif ($st.Hover) { (RGB 170 33 24) } else { $C.Err }
                $textColor = $C.White
            }
            'quiet' {
                $fillColor = if ($st.Hover) { $C.Border } else { $bg }
                $textColor = $C.TextSoft
            }
            default {
                $fillColor   = if ($st.Down) { (RGB 236 236 238) } elseif ($st.Hover) { $C.Muted } else { $C.White }
                $borderColor = $C.Border
            }
        }

        # A disabled button has to look disabled, or people keep clicking it.
        if (-not $s.Enabled) {
            $fillColor   = (RGB 234 234 237)
            $textColor   = (RGB 150 150 156)
            $borderColor = $null
        }

        $brush = New-Object System.Drawing.SolidBrush($fillColor)
        $gfx.FillPath($brush, $path)
        $brush.Dispose()

        if ($borderColor) {
            $pen = New-Object System.Drawing.Pen($borderColor, 1)
            $gfx.DrawPath($pen, $path)
            $pen.Dispose()
        }

        $fmt = New-Object System.Drawing.StringFormat
        $fmt.Alignment     = 'Center'
        $fmt.LineAlignment = 'Center'
        $tb = New-Object System.Drawing.SolidBrush($textColor)
        $gfx.DrawString($s.Text, $s.Font, $tb, ([System.Drawing.RectangleF]$rect), $fmt)
        $tb.Dispose()
        $fmt.Dispose()

        # Keyboard focus ring, so Tab and Enter users can see where they are.
        if ($s.Focused -and $script:KbNav) {
            $ring = New-Object System.Drawing.Rectangle(2, 2, ($s.Width - 5), ($s.Height - 5))
            $rp   = New-RoundedPath -Rect $ring -Radius 5
            $rc   = if ($st.Kind -eq 'primary' -or $st.Kind -eq 'danger') { $C.White } else { $C.Accent }
            $rpen = New-Object System.Drawing.Pen($rc, 2)
            $gfx.DrawPath($rpen, $rp)
            $rpen.Dispose(); $rp.Dispose()
        }
        $path.Dispose()
    })
    $b.Add_GotFocus({  $this.Invalidate() })
    $b.Add_LostFocus({ $this.Invalidate() })
    return $b
}

function New-T2FHeading {
    param([string]$Text, [single]$Size = 13)
    $l = New-Object System.Windows.Forms.Label
    $l.Text        = $Text
    $l.Font        = (New-T2FFont $Size 'Semibold')
    $l.ForeColor   = $C.Text
    $l.AutoSize    = $true
    $l.MaximumSize = New-Object System.Drawing.Size($UI.Body, 0)
    $l.Margin      = New-Object System.Windows.Forms.Padding(0, 6, 0, 4)
    return $l
}

function New-T2FText {
    param([string]$Text, [single]$Size = 10, $Color = $null, [int]$MaxWidth = $UI.Body, [string]$Weight = 'Regular')
    $l = New-Object System.Windows.Forms.Label
    $l.Text        = $Text
    $l.Font        = (New-T2FFont $Size $Weight)
    $l.ForeColor   = if ($Color) { $Color } else { $C.TextSoft }
    $l.AutoSize    = $true
    $l.MaximumSize = New-Object System.Drawing.Size($MaxWidth, 0)
    $l.Margin      = New-Object System.Windows.Forms.Padding(0, 2, 0, 6)
    return $l
}

function New-T2FCard {
    param([int]$Width = $UI.Card, $Accent = $null, $Fill = $null)
    $p = New-Object System.Windows.Forms.FlowLayoutPanel
    $p.FlowDirection = 'TopDown'
    $p.WrapContents  = $false
    $p.AutoSize      = $true
    $p.AutoSizeMode  = 'GrowOnly'
    # With AutoSize on, Width is recomputed from content and every card would end up
    # a different size. Pinning both bounds keeps the stack aligned.
    $p.MinimumSize   = New-Object System.Drawing.Size($Width, 0)
    $p.MaximumSize   = New-Object System.Drawing.Size($Width, 0)
    $p.Padding       = New-Object System.Windows.Forms.Padding(18, 14, 18, 14)
    $p.Margin        = New-Object System.Windows.Forms.Padding(0, 4, 0, 10)
    $p.BackColor     = if ($Fill) { $Fill } else { $C.Surface }
    $p.Tag           = $Accent
    $p.Add_Paint({
        param($s, $e)
        $gfx = $e.Graphics
        $gfx.SmoothingMode = 'AntiAlias'
        # Repaint the corners with the page color so the rounding is visible.
        $bg = $s.Parent.BackColor
        if ($bg.A -eq 0) { $bg = $C.Page }
        $gfx.Clear($bg)
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $path = New-RoundedPath -Rect $rect -Radius 8
        $brush = New-Object System.Drawing.SolidBrush($s.BackColor)
        $gfx.FillPath($brush, $path)
        $brush.Dispose()
        $pen = New-Object System.Drawing.Pen($(if ($s.Tag) { $s.Tag } else { $C.Border }), 1)
        $gfx.DrawPath($pen, $path)
        $pen.Dispose()
        # Accent cards get a heavier left rule so the state reads at a glance.
        if ($s.Tag) {
            $accentBrush = New-Object System.Drawing.SolidBrush($s.Tag)
            $gfx.FillRectangle($accentBrush, 1, 9, 3, ($s.Height - 18))
            $accentBrush.Dispose()
        }
        $path.Dispose()
    })
    return $p
}

function New-T2FStatusRow {
    param(
        [string]$Label,
        [string]$Value,
        [ValidateSet('ok','warn','err','info')][string]$State = 'info',
        [int]$Width = $UI.Inner
    )
    $glyph = switch ($State) { 'ok' { $G.Check } 'warn' { $G.Warning } 'err' { $G.Cross } default { $G.Info } }
    $color = switch ($State) { 'ok' { $C.Ok }    'warn' { $C.Warn }    'err' { $C.Err }   default { $C.TextSoft } }

    $t = New-Object System.Windows.Forms.TableLayoutPanel
    $t.ColumnCount = 3
    $t.RowCount    = 1
    $t.AutoSize    = $true
    $t.AutoSizeMode= 'GrowOnly'
    $t.MinimumSize = New-Object System.Drawing.Size($Width, 0)
    $t.MaximumSize = New-Object System.Drawing.Size($Width, 0)
    $t.Margin      = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
    $t.BackColor   = [System.Drawing.Color]::Transparent
    $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 26)))  | Out-Null
    $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 168))) | Out-Null
    $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))  | Out-Null

    $ic = New-Object System.Windows.Forms.Label
    $ic.Text      = [string]$glyph
    $ic.Font      = (New-T2FIconFont 11)
    $ic.ForeColor = $color
    $ic.AutoSize  = $true
    $ic.Margin    = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
    $t.Controls.Add($ic, 0, 0)

    $lb = New-Object System.Windows.Forms.Label
    $lb.Text      = $Label
    $lb.Font      = (New-T2FFont 10)
    $lb.ForeColor = $C.TextSoft
    $lb.AutoSize  = $true
    $t.Controls.Add($lb, 1, 0)

    $vl = New-Object System.Windows.Forms.Label
    $vl.Text        = $Value
    $vl.Font        = (New-T2FFont 10 'Semibold')
    $vl.ForeColor   = if ($State -eq 'info') { $C.Text } else { $color }
    $vl.AutoSize    = $true
    $vl.MaximumSize = New-Object System.Drawing.Size(($Width - 200), 0)
    $t.Controls.Add($vl, 2, 0)

    $t | Add-Member -NotePropertyName IconLabel  -NotePropertyValue $ic -Force
    $t | Add-Member -NotePropertyName ValueLabel -NotePropertyValue $vl -Force
    return $t
}

# Holds buttons inside a card. The button Paint reads its parent's BackColor, so the
# row has to carry the card's fill or the rounded corners show the wrong color.
function New-T2FButtonRow {
    param($Fill = $null)
    $row = New-Object System.Windows.Forms.FlowLayoutPanel
    $row.FlowDirection = 'LeftToRight'
    $row.WrapContents  = $true
    $row.AutoSize      = $true
    $row.AutoSizeMode  = 'GrowAndShrink'
    $row.BackColor     = if ($Fill) { $Fill } else { $C.Surface }
    $row.Margin        = New-Object System.Windows.Forms.Padding(0, 8, 0, 2)
    return $row
}

# Rounded progress bar. Tag.Value is 0-100, or -1 when the amount is not known yet,
# in which case a soft segment glides across so the user can see it is working.
function New-T2FProgress {
    param([int]$Width = $UI.Inner, [int]$Height = 14)
    $p = New-Object System.Windows.Forms.Panel
    $p.Size   = New-Object System.Drawing.Size($Width, $Height)
    $p.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 6)
    $p.Tag    = [pscustomobject]@{ Value = 0; Phase = 0 }
    $p.Add_Paint({
        param($s, $e)
        $gfx = $e.Graphics
        $gfx.SmoothingMode = 'AntiAlias'
        $bg = $s.Parent.BackColor
        if ($bg.A -eq 0) { $bg = $C.Page }
        $gfx.Clear($bg)

        $w = $s.Width - 1; $h = $s.Height - 1
        $track = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
        $tp    = New-RoundedPath -Rect $track -Radius ([int]($h / 2))
        $tb    = New-Object System.Drawing.SolidBrush($C.Border)
        $gfx.FillPath($tb, $tp); $tb.Dispose()

        $v = [double]$s.Tag.Value
        $gfx.SetClip($tp)
        if ($v -ge 0) {
            $fw = [int][Math]::Round($w * [Math]::Min([double]100, $v) / 100)
            if ($fw -gt 0) {
                $fr = New-Object System.Drawing.Rectangle(0, 0, [Math]::Max($fw, $h), $h)
                $fb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($fr, $C.Accent, $C.AccentDark, 0.0)
                $gfx.FillRectangle($fb, $fr); $fb.Dispose()
            }
        } else {
            $seg   = [int]($w * 0.32)
            $cycle = $w + $seg
            $x     = (($s.Tag.Phase * 14) % $cycle) - $seg
            $fr    = New-Object System.Drawing.Rectangle($x, 0, $seg, $h)
            $fb    = New-Object System.Drawing.Drawing2D.LinearGradientBrush($fr, $C.Accent, $C.AccentDark, 0.0)
            $gfx.FillRectangle($fb, $fr); $fb.Dispose()
        }
        $gfx.ResetClip()
        $tp.Dispose()
    })
    return $p
}

# Numbered step marker: a filled circle with the number, or a tick once it is done,
# followed by the step title. Tag.State is 'todo', 'active' or 'done'.
function New-T2FStepHeader {
    param([int]$Number, [string]$Title, [string]$State = 'todo', [int]$Width = $UI.Inner)
    $p = New-Object System.Windows.Forms.Panel
    $p.Size   = New-Object System.Drawing.Size($Width, 38)
    $p.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
    $p.Tag    = [pscustomobject]@{ Number = $Number; Title = $Title; State = $State }
    $p.Add_Paint({
        param($s, $e)
        $gfx = $e.Graphics
        $gfx.SmoothingMode     = 'AntiAlias'
        $gfx.TextRenderingHint = 'ClearTypeGridFit'
        $bg = $s.Parent.BackColor
        if ($bg.A -eq 0) { $bg = $C.Page }
        $gfx.Clear($bg)

        $st = $s.Tag
        $fill = switch ($st.State) { 'done' { $C.Ok } 'active' { $C.Accent } default { (RGB 176 176 182) } }
        $circle = New-Object System.Drawing.Rectangle(0, 3, 30, 30)
        $cb = New-Object System.Drawing.SolidBrush($fill)
        $gfx.FillEllipse($cb, $circle); $cb.Dispose()

        $wb = New-Object System.Drawing.SolidBrush($C.White)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        if ($st.State -eq 'done') { $f = New-T2FIconFont 11; $txt = [string]$G.Check } else { $f = New-T2FFont 10 'Semibold'; $txt = [string]$st.Number }
        $gfx.DrawString($txt, $f, $wb, ([System.Drawing.RectangleF]$circle), $sf)
        $f.Dispose(); $sf.Dispose(); $wb.Dispose()

        $tf  = New-T2FFont 11 'Semibold'
        $col = if ($st.State -eq 'todo') { $C.TextSoft } else { $C.Text }
        $tbr = New-Object System.Drawing.SolidBrush($col)
        $sf2 = New-Object System.Drawing.StringFormat
        $sf2.LineAlignment = 'Center'
        $gfx.DrawString($st.Title, $tf, $tbr, (New-Object System.Drawing.RectangleF(42, 0, ($s.Width - 42), $s.Height)), $sf2)
        $tf.Dispose(); $tbr.Dispose(); $sf2.Dispose()
    })
    return $p
}

function New-T2FLink {
    param([string]$Text, [string]$Url)
    $lnk = New-Object System.Windows.Forms.LinkLabel
    $lnk.Text             = $Text
    $lnk.Font             = (New-T2FFont 9.5)
    $lnk.AutoSize         = $true
    $lnk.UseMnemonic      = $false
    $lnk.LinkColor        = $C.AccentDark
    $lnk.ActiveLinkColor  = $C.Accent
    $lnk.VisitedLinkColor = $C.AccentDark
    $lnk.LinkBehavior     = 'HoverUnderline'
    $lnk.Margin           = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
    $lnk.Tag              = $Url
    $lnk.Add_LinkClicked({
        Open-T2FDownload -Title 'Open your web browser?' -What "the page `"$($this.Text)`"" -Url $this.Tag
    })
    return $lnk
}

$script:ChoiceGroup    = @()
$script:ChoiceUpdating = $false

function New-T2FChoice {
    param(
        [string]$Title,
        [string]$Description,
        [bool]$IsChecked = $false,
        [bool]$IsEnabled = $true,
        [string]$Badge = '',
        [int]$Width = $UI.Card
    )
    $card = New-Object System.Windows.Forms.Panel
    $card.Width  = $Width
    $card.Height = 78
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $card.Cursor = if ($IsEnabled) { [System.Windows.Forms.Cursors]::Hand } else { [System.Windows.Forms.Cursors]::Default }
    # The radio and description are transparent, so they render against the card's
    # BackColor. Driving the fill from BackColor keeps them in step with the paint.
    $card.BackColor = if (-not $IsEnabled) { $C.Muted } elseif ($IsChecked) { $C.AccentSoft } else { $C.White }

    $radio = New-Object System.Windows.Forms.RadioButton
    $radio.Text      = $Title
    $radio.Font      = (New-T2FFont 10.5 'Semibold')
    $radio.ForeColor = if ($IsEnabled) { $C.Text } else { $C.Disabled }
    $radio.AutoSize  = $true
    $radio.Enabled   = $IsEnabled
    $radio.Checked   = $IsChecked
    $radio.BackColor = [System.Drawing.Color]::Transparent
    $radio.Location  = New-Object System.Drawing.Point(16, 14)
    $card.Controls.Add($radio)

    $desc = New-Object System.Windows.Forms.Label
    $desc.Text        = $Description
    $desc.Font        = (New-T2FFont 9.5)
    $desc.ForeColor   = if ($IsEnabled) { $C.TextSoft } else { $C.DisabledSub }
    $desc.AutoSize    = $true
    $desc.MaximumSize = New-Object System.Drawing.Size(($Width - 160), 0)
    $desc.BackColor   = [System.Drawing.Color]::Transparent
    $desc.Location    = New-Object System.Drawing.Point(37, 38)
    $card.Controls.Add($desc)

    if ($Badge) {
        $bg = New-Object System.Windows.Forms.Label
        $bg.Text      = $Badge
        $bg.Font      = (New-T2FFont 8 'Semibold')
        $bg.ForeColor = $C.White
        $bg.BackColor = $C.Ok
        $bg.AutoSize  = $true
        $bg.Padding   = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
        $bg.Location  = New-Object System.Drawing.Point(($Width - 122), 16)
        $card.Controls.Add($bg)
    }

    $card.Tag = $radio
    $card.Add_Paint({
        param($s, $e)
        $gfx = $e.Graphics
        $gfx.SmoothingMode = 'AntiAlias'
        $bg = $s.Parent.BackColor
        if ($bg.A -eq 0) { $bg = $C.Page }
        $gfx.Clear($bg)
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $path = New-RoundedPath -Rect $rect -Radius 8
        $brush = New-Object System.Drawing.SolidBrush($s.BackColor)
        $gfx.FillPath($brush, $path)
        $brush.Dispose()
        $on = $s.Tag.Checked
        $pen = New-Object System.Drawing.Pen($(if ($on) { $C.Accent } else { $C.Border }), $(if ($on) { 2 } else { 1 }))
        $gfx.DrawPath($pen, $path)
        $pen.Dispose()
        $path.Dispose()
    })

    $select = {
        $r = $this.Tag
        if ($null -eq $r) { $r = $this.Parent.Tag }
        if ($r -and $r.Enabled) { $r.Checked = $true }
    }
    $card.Add_Click($select)
    $desc.Add_Click($select)

    # Each radio lives in its own card, and WinForms only auto-excludes radios that
    # share a parent, so the group behaviour is enforced here. The guard stops the
    # cascade of CheckedChanged events this raises from re-entering.
    # Not $c for the loop variable: names are case-insensitive, so it would shadow
    # the $C color palette and every lookup below would return null.
    $radio.Add_CheckedChanged({
        if ($script:ChoiceUpdating) { return }
        $script:ChoiceUpdating = $true
        try {
            if ($this.Checked) {
                foreach ($item in $script:ChoiceGroup) {
                    if ($item.Tag -ne $this) { $item.Tag.Checked = $false }
                }
            }
            foreach ($item in $script:ChoiceGroup) {
                $item.BackColor = if (-not $item.Tag.Enabled) { $C.Muted } elseif ($item.Tag.Checked) { $C.AccentSoft } else { $C.White }
                $item.Invalidate()
            }
        } finally { $script:ChoiceUpdating = $false }
    })

    # Re-layout now that the description's wrapped height is known.
    $card.Height = [Math]::Max(78, $desc.Location.Y + $desc.PreferredHeight + 16)

    $script:ChoiceGroup += $card
    return $card
}

# Themed stand-in for MessageBox so every prompt matches the rest of the tool.
function Show-T2FDialog {
    param(
        [string]$Title,
        [string]$Message,
        [ValidateSet('ok','warn','err','info')][string]$State = 'info',
        [string[]]$Buttons = @('OK'),
        [string]$Primary = '',
        [string]$Detail = '',
        [string]$CopyText = ''
    )
    $glyph = switch ($State) { 'ok' { $G.Check } 'warn' { $G.Warning } 'err' { $G.Cross } default { $G.Info } }
    $color = switch ($State) { 'ok' { $C.Ok }    'warn' { $C.Warn }    'err' { $C.Err }   default { $C.Accent } }
    $soft  = switch ($State) { 'ok' { $C.OkSoft } 'warn' { $C.WarnSoft } 'err' { $C.ErrSoft } default { $C.AccentSoft } }
    # A "Copy link" button is inserted just before the last (confirm) button and
    # keeps the dialog open, so the user can copy the address and still choose.
    if ($CopyText) { $Buttons = @($Buttons[0..($Buttons.Count - 2)]) + @('Copy link') + @($Buttons[-1]) }
    $script:DialogCopyText = $CopyText
    Log "Dialog: $Title"

    $w = $UI.Dialog
    $form = New-Object System.Windows.Forms.Form
    $form.Text            = 'Tips2Fix'
    $form.StartPosition   = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MinimizeBox     = $false
    $form.MaximizeBox     = $false
    $form.AutoScaleMode   = 'Dpi'
    $form.BackColor       = $C.Page
    $form.Font            = (New-T2FFont 10)

    $body = New-Object System.Windows.Forms.FlowLayoutPanel
    $body.FlowDirection = 'TopDown'
    $body.WrapContents  = $false
    $body.AutoSize      = $true
    $body.AutoSizeMode  = 'GrowAndShrink'
    $body.Location      = New-Object System.Drawing.Point(26, 24)
    $body.Width         = $w - 52
    $body.BackColor     = $C.Page
    $form.Controls.Add($body)

    $head = New-Object System.Windows.Forms.TableLayoutPanel
    $head.ColumnCount = 2
    $head.RowCount    = 1
    $head.AutoSize    = $true
    $head.Margin      = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
    $head.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', 46))) | Out-Null
    $head.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null

    $chip = New-Object System.Windows.Forms.Label
    $chip.Text      = [string]$glyph
    $chip.Font      = (New-T2FIconFont 17)
    $chip.ForeColor = $color
    $chip.BackColor = $soft
    $chip.Size      = New-Object System.Drawing.Size(36, 36)
    $chip.TextAlign = 'MiddleCenter'
    $head.Controls.Add($chip, 0, 0)

    $tl = New-Object System.Windows.Forms.Label
    $tl.Text        = $Title
    $tl.Font        = (New-T2FFont 13 'Semibold')
    $tl.ForeColor   = $C.Text
    $tl.AutoSize    = $true
    $tl.MaximumSize = New-Object System.Drawing.Size(($w - 120), 0)
    $tl.Margin      = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
    $head.Controls.Add($tl, 1, 0)
    $body.Controls.Add($head)

    $body.Controls.Add((New-T2FText -Text $Message -Size 10 -Color $C.Text -MaxWidth ($w - 60)))
    if ($Detail) {
        $card = New-T2FCard -Width ($w - 58) -Accent $color -Fill $soft
        $card.Controls.Add((New-T2FText -Text $Detail -Size 9.5 -Color $C.Text -MaxWidth ($w - 110)))
        $body.Controls.Add($card)
    }

    # Fixed width, not AutoSize: a shrink-to-fit panel would park the buttons on
    # the left instead of letting RightToLeft push them to the right edge.
    $bar = New-Object System.Windows.Forms.FlowLayoutPanel
    $bar.FlowDirection = 'RightToLeft'
    $bar.WrapContents  = $false
    $bar.AutoSize      = $false
    $bar.Size          = New-Object System.Drawing.Size(($w - 56), 48)
    $bar.Margin        = New-Object System.Windows.Forms.Padding(0, 12, 0, 0)
    $bar.BackColor     = $C.Page
    $body.Controls.Add($bar)

    $script:DialogResult = $null
    if (-not $Primary) { $Primary = $Buttons[0] }
    foreach ($label in $Buttons) {
        $kind = if ($label -eq $Primary) { if ($State -eq 'err') { 'danger' } else { 'primary' } } else { 'secondary' }
        $btn = New-T2FButton -Text $label -Kind $kind
        $btn | Add-Member -NotePropertyName ChoiceLabel -NotePropertyValue $label -Force
        if ($label -eq 'Copy link') {
            $btn.Add_Click({
                try {
                    [System.Windows.Forms.Clipboard]::SetText($script:DialogCopyText)
                    Log 'Copied link to clipboard.'
                    $this.Text = 'Copied'
                } catch {
                    Log "Clipboard unavailable: $($_.Exception.Message)"
                    $this.Text = 'Copy failed'
                }
                $this.Invalidate()
            })
        } else {
            $btn.Add_Click({ $script:DialogResult = $this.ChoiceLabel; $form.Close() })
        }
        $bar.Controls.Add($btn)
    }

    $form.ClientSize = New-Object System.Drawing.Size($w, ($body.PreferredSize.Height + 52))
    $form.Add_Shown({
        try { $this.TopMost = $true; $this.TopMost = $false; $this.Activate() } catch {}
    })
    # The newest visible window of this tool owns the dialog, so the dialog always sits
    # in front of it and moves with it. (ActiveForm is null whenever another program has
    # focus, which would leave the dialog free to fall behind.)
    $owner = @([System.Windows.Forms.Application]::OpenForms | Where-Object { $_.Visible -and -not $_.IsDisposed }) | Select-Object -Last 1
    if ($owner) { $form.ShowDialog($owner) | Out-Null } else { $form.ShowDialog() | Out-Null }
    $form.Dispose()
    return $script:DialogResult
}

function Confirm-T2F {
    param(
        [string]$Title, [string]$Message, [string]$Detail = '',
        [string]$YesText = 'Continue', [string]$NoText = 'Cancel', [string]$State = 'info',
        [string]$CopyText = ''
    )
    return ((Show-T2FDialog -Title $Title -Message $Message -Detail $Detail -State $State `
                            -Buttons @($NoText, $YesText) -Primary $YesText -CopyText $CopyText) -eq $YesText)
}

function Inform-T2F {
    param([string]$Title, [string]$Message, [string]$Detail = '', [string]$State = 'info')
    Show-T2FDialog -Title $Title -Message $Message -Detail $Detail -State $State -Buttons @('Close') | Out-Null
}

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

# ===================== System detection =====================

# SSE4.2 cannot be bypassed by any registry key: without it Windows 11 24H2+
# will not boot at all, so this result decides whether the script may continue.
function Get-Sse42Support {
    try {
        if (-not ('Tips2Fix.CpuFeature' -as [type])) {
            Add-Type -Namespace 'Tips2Fix' -Name 'CpuFeature' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
[return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
public static extern bool IsProcessorFeaturePresent(uint ProcessorFeature);
'@
        }
        # PF_SSE4_2_INSTRUCTIONS_AVAILABLE
        $sse42 = [Tips2Fix.CpuFeature]::IsProcessorFeaturePresent(38)
        return [pscustomobject]@{ Supported = [bool]$sse42; Method = 'Windows API' }
    } catch {
        Log "SSE4.2 API check unavailable ($($_.Exception.Message)); falling back to CPU name heuristic."
    }

    $name = ''
    try { $name = ((Get-CimInstance Win32_Processor -ErrorAction Stop) | Select-Object -First 1).Name.Trim() } catch {}

    $guess = $null
    if ($name -match 'Intel') {
        if     ($name -match 'Core 2|Pentium D|Atom N2|Atom D5')                            { $guess = $false }
        elseif ($name -match 'Core.*i[3579]|Xeon|Ultra|Silver|Gold|Platinum')               { $guess = $true }
    } elseif ($name -match 'AMD') {
        if     ($name -match 'Ryzen|EPYC|Threadripper|FX-|Athlon (Gold|Silver)')            { $guess = $true }
        elseif ($name -match 'Phenom|Athlon 64|Athlon II|Turion|Sempron')                   { $guess = $false }
    }
    return [pscustomobject]@{ Supported = $guess; Method = 'CPU name heuristic' }
}

# ===================== Hardware report =====================

# Reads the facts that Windows 11's requirements are about. Every read is read-only.
# Anything that cannot be read is left as $null, so the screen says "could not be read"
# instead of guessing.
function Get-HardwareFacts {
    $f = [ordered]@{
        CpuName = $null; Cores = $null; Threads = $null; MaxMHz = $null
        Firmware = $null; SecureBoot = $null; TpmPresent = $null; TpmSpec = $null
        RamGB = $null; DiskGB = $null; DiskFreeGB = $null
    }

    try {
        $cpus = @(Get-CimInstance Win32_Processor -ErrorAction Stop)
        if ($cpus.Count -gt 0) {
            $f.CpuName = ($cpus[0].Name -replace '\s+', ' ').Trim()
            $f.Cores   = [int](($cpus | Measure-Object -Property NumberOfCores -Sum).Sum)
            $f.Threads = [int](($cpus | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum)
            $f.MaxMHz  = [int]$cpus[0].MaxClockSpeed
        }
    } catch {}

    $uefi = Test-UefiFirmware
    $f.Firmware = if ($uefi -eq $true) { 'UEFI' } elseif ($uefi -eq $false) { 'Legacy BIOS' } else { $null }
    if ($uefi -eq $true) {
        try { $f.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) }
        catch {
            # Needs administrator rights; the registry copy of the same answer does not.
            try {
                $v = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -Name UEFISecureBootEnabled -ErrorAction Stop
                $f.SecureBoot = ([int]$v.UEFISecureBootEnabled -eq 1)
            } catch {}
        }
    } elseif ($uefi -eq $false) {
        $f.SecureBoot = $false
    }

    try {
        $tpm = @(Get-CimInstance -Namespace 'root\cimv2\Security\MicrosoftTpm' -ClassName Win32_Tpm -ErrorAction Stop)
        if ($tpm.Count -gt 0) {
            $f.TpmPresent = $true
            $f.TpmSpec    = (([string]$tpm[0].SpecVersion) -split ',')[0].Trim()
        } else {
            $f.TpmPresent = $false
        }
    } catch {}

    try { $f.RamGB = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory / 1GB, 1) } catch {}
    try {
        $d = Get-CimInstance Win32_LogicalDisk -Filter ("DeviceID='" + $env:SystemDrive + "'") -ErrorAction Stop
        $f.DiskGB     = [math]::Round($d.Size / 1GB)
        $f.DiskFreeGB = [math]::Round($d.FreeSpace / 1GB)
    } catch {}

    return [pscustomobject]$f
}

# Turns the facts into rows for the screen, one per Windows 11 requirement. State is
# 'ok' (meets it), 'warn' (below it, and the tool tells Setup to skip that check),
# or 'info' (nothing to judge, or it could not be read).
function Get-HardwareRows {
    param($Facts)

    $rows = New-Object System.Collections.ArrayList
    $skip = ' (this tool skips it)'
    $add  = { param($Label, $Value, $State) [void]$rows.Add([pscustomobject]@{ Label = $Label; Value = $Value; State = $State }) }

    & $add 'Processor' $(if ($Facts.CpuName) { $Facts.CpuName } else { 'Could not be read' }) 'info'

    if ($null -eq $Facts.Cores -or $null -eq $Facts.MaxMHz) {
        & $add 'Cores and speed' 'Could not be read' 'info'
    } else {
        $ghz  = '{0:N1} GHz' -f ($Facts.MaxMHz / 1000)
        $text = "$($Facts.Cores) cores, $($Facts.Threads) threads, $ghz"
        if ($Facts.Cores -ge 2 -and $Facts.MaxMHz -ge 1000) { & $add 'Cores and speed' $text 'ok' }
        else { & $add 'Cores and speed' ($text + ', needs 2 cores at 1 GHz' + $skip) 'warn' }
    }

    # Windows reports a little under the installed amount, so 3.5 GB counts as 4 GB.
    if ($null -eq $Facts.RamGB) { & $add 'Memory' 'Could not be read' 'info' }
    elseif ($Facts.RamGB -ge 3.5) { & $add 'Memory' ('{0:N0} GB' -f [math]::Round($Facts.RamGB)) 'ok' }
    else { & $add 'Memory' (('{0:N1} GB, needs 4 GB' -f $Facts.RamGB) + $skip) 'warn' }

    # A "64 GB" drive shows as about 59 GB, so 55 GB counts as meeting the minimum.
    if ($null -eq $Facts.DiskGB) { & $add 'Storage' 'Could not be read' 'info' }
    else {
        $t = "$($Facts.DiskGB) GB system drive, $($Facts.DiskFreeGB) GB free"
        if ($Facts.DiskGB -ge 55) { & $add 'Storage' $t 'ok' } else { & $add 'Storage' ($t + ', needs 64 GB' + $skip) 'warn' }
    }

    if (-not $Facts.Firmware) { & $add 'Firmware' 'Could not be read' 'info' }
    elseif ($Facts.Firmware -eq 'UEFI') { & $add 'Firmware' 'UEFI' 'ok' }
    else { & $add 'Firmware' ('Legacy BIOS, UEFI is recommended' + $skip) 'warn' }

    if ($Facts.Firmware -eq 'Legacy BIOS') { & $add 'Secure Boot' ('Not available on Legacy BIOS' + $skip) 'warn' }
    elseif ($null -eq $Facts.SecureBoot) { & $add 'Secure Boot' 'Could not be read' 'info' }
    elseif ($Facts.SecureBoot) { & $add 'Secure Boot' 'Enabled' 'ok' }
    else { & $add 'Secure Boot' ('Disabled or not supported' + $skip) 'warn' }

    if ($null -eq $Facts.TpmPresent) { & $add 'TPM' 'Could not be read (needs administrator rights)' 'info' }
    elseif (-not $Facts.TpmPresent) { & $add 'TPM' ('Not found, needs TPM 2.0' + $skip) 'warn' }
    elseif ($Facts.TpmSpec -eq '2.0') { & $add 'TPM' 'TPM 2.0' 'ok' }
    else { & $add 'TPM' ("TPM $($Facts.TpmSpec), needs 2.0" + $skip) 'warn' }

    & $add 'Microsoft''s CPU list' 'Not checked here. PC Health Check gives Microsoft''s verdict' 'info'

    return ,$rows.ToArray()
}

# Reads the hardware while a small window says so, because the TPM query alone can
# take several seconds and a screen that just sits there looks frozen.
function Get-HardwareReport {
    $win = New-T2FWindow -Title 'Reading your hardware' -Subtitle 'This takes a few seconds.' -Width 660 -NoAbout
    $win.Form.ControlBox = $false
    $win.Body.Controls.Add((New-T2FText -Text ('Checking the processor, memory, storage, firmware, Secure Boot and TPM. ' +
        'This only reads information and changes nothing.') -Size 10 -Color $C.Text -MaxWidth 580))
    $bar = New-T2FProgress -Width 580 -Height 14
    $bar.Tag.Value = -1
    $win.Body.Controls.Add($bar)
    $win.Form.ClientSize = New-Object System.Drawing.Size(660, ($win.HeaderHeight + 190))
    $win.Form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $facts = Get-HardwareFacts
    } finally {
        $win.Form.Close()
        $win.Form.Dispose()
    }
    return [pscustomobject]@{ Facts = $facts; Rows = (Get-HardwareRows -Facts $facts) }
}

# One plain-language conclusion under the table.
function Get-HardwareSummary {
    param($Rows, $Sse)

    $below = @($Rows | Where-Object { $_.State -eq 'warn' } | ForEach-Object { $_.Label })
    if ($Sse.Supported -eq $false) {
        return [pscustomobject]@{ State = 'err'
            Text = "This processor lacks SSE4.2, so Windows 11 $TargetName cannot run on it. Nothing in this tool can change that." }
    }
    if ($below.Count -gt 0) {
        $list = $below -join ', '
        return [pscustomobject]@{ State = 'warn'
            Text = ("Below Microsoft's minimum: $list. That is normal for an older PC. This tool sets Windows Setup to skip these checks, " +
                    'so they do not stop you. Microsoft calls such a PC unsupported and does not promise updates for it.') }
    }
    return [pscustomobject]@{ State = 'ok'
        Text = ('Everything this tool can read meets Microsoft''s minimum, so you may not need the bypass at all. ' +
                'It cannot check Microsoft''s list of supported processors; PC Health Check can.') }
}

function Get-OsInfo {
    $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = 0
    [void][int]::TryParse([string]$k.CurrentBuildNumber, [ref]$build)

    $friendly = switch ($build) {
        19044   { 'Windows 10 21H2' }
        19045   { 'Windows 10 22H2' }
        22000   { 'Windows 11 21H2' }
        22621   { 'Windows 11 22H2' }
        22631   { 'Windows 11 23H2' }
        26100   { 'Windows 11 24H2' }
        26200   { 'Windows 11 25H2' }
        26300   { 'Windows 11 26H2' }
        default {
            if ($build -ge 22000) { "Windows 11 (build $build)" } else { "Windows 10 (build $build)" }
        }
    }

    return [pscustomobject]@{
        Build      = $build
        UBR        = $k.UBR
        Friendly   = $friendly
        IsWin10    = ($build -lt 22000)
        EkbCapable = ($EkbEligible -contains $build)
        AlreadyOn  = ($build -ge $TargetBuild)
    }
}

# ProductName in the registry still reports "Windows 10" on Windows 11, so the
# edition is derived from EditionID instead.
function Get-InstalledEditionInfo {
    $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $editionId = [string]$k.EditionID

    $edition = $EditionIdMap[$editionId]
    if (-not $edition) { $edition = $editionId }

    $langTag = 'en-US'; $langName = 'English (United States)'
    try {
        $ui = Get-UICulture
        $langTag  = $ui.Name
        $langName = [System.Globalization.CultureInfo]::GetCultureInfo($langTag).EnglishName
    } catch {}

    $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
        'AMD64' { 'x64' }
        'ARM64' { 'ARM64' }
        'x86'   { '32-bit (x86)' }
        default { [string]$env:PROCESSOR_ARCHITECTURE }
    }

    return [pscustomobject]@{
        EditionId    = $editionId
        Edition      = $edition
        LanguageTag  = $langTag
        LanguageName = $langName
        Architecture = $arch
    }
}

function Get-FreeSpaceBytes {
    param([string]$Path)
    try {
        $qualifier = (Split-Path -Path $Path -Qualifier)
        $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$qualifier'" -ErrorAction Stop
        return [long]$d.FreeSpace
    } catch { return -1 }
}

# sources\idwbinfo.txt is a plain text stamp on every Windows ISO; reading it is
# far faster than inspecting install.wim/install.esd with Get-WindowsImage.
function Get-IsoBuildInfo {
    param([string]$Root)
    $build = 0
    $lab   = ''
    $idw = Join-Path $Root 'sources\idwbinfo.txt'
    if (Test-Path -LiteralPath $idw) {
        foreach ($line in (Get-Content -LiteralPath $idw -ErrorAction SilentlyContinue)) {
            if ($line -match 'BuildNumber\s*=\s*(\d+)') { $build = [int]$Matches[1] }
            if ($line -match 'BuildLab\s*=\s*(.+)')     { $lab   = $Matches[1].Trim() }
        }
    }
    return [pscustomobject]@{ Build = $build; BuildLab = $lab }
}

# Setup silently drops the "keep files and apps" option when the media language
# does not match the installed one, so lang.ini is worth reading up front.
function Get-IsoLanguages {
    param([string]$Root)
    $langs = @()
    $ini = Join-Path $Root 'sources\lang.ini'
    if (Test-Path -LiteralPath $ini) {
        $inSection = $false
        foreach ($line in (Get-Content -LiteralPath $ini -ErrorAction SilentlyContinue)) {
            $trimmed = $line.Trim()
            if ($trimmed.StartsWith('[') -and $trimmed.EndsWith(']')) {
                $inSection = ($trimmed -match 'Available UI Languages')
                continue
            }
            if ($inSection -and $trimmed -match '^([A-Za-z]{2}-[A-Za-z0-9-]+)\s*=') { $langs += $Matches[1] }
        }
    }
    # The leading comma stops PowerShell unwrapping a single-entry result into a bare string.
    return ,@($langs | Select-Object -Unique)
}

function Get-IsoEditions {
    param([string]$Root)
    foreach ($rel in 'sources\install.wim','sources\install.esd') {
        $p = Join-Path $Root $rel
        if (Test-Path -LiteralPath $p) {
            try { return ,@(Get-WindowsImage -ImagePath $p -ErrorAction Stop | ForEach-Object { [string]$_.ImageName }) }
            catch { Log "Could not read editions from $rel : $($_.Exception.Message)"; return ,@() }
        }
    }
    return ,@()
}

function Resolve-SetupPath {
    param([string]$Root)
    $prep = Join-Path $Root 'sources\setupprep.exe'
    $exe  = Join-Path $Root 'setup.exe'
    if (Test-Path -LiteralPath $prep) { return $prep }
    if (Test-Path -LiteralPath $exe)  { return $exe }
    return $null
}

# ===================== Registry bypass =====================

function Apply-Bypass {
    Log 'Applying bypass registry keys...'

    New-Item -Path $LabConfigPath -Force | Out-Null
    foreach ($n in $LabConfigValues) { Set-ItemProperty $LabConfigPath -Name $n -Value 1 -Type DWord }

    New-Item -Path $MoSetupPath -Force | Out-Null
    Set-ItemProperty $MoSetupPath -Name 'AllowUpgradesWithUnsupportedTPMOrCPU' -Value 1 -Type DWord

    # Makes the compatibility appraiser report a passing result. This is what keeps
    # "Keep personal files and apps" selectable during a Windows 10 in-place upgrade,
    # which the /product server workaround would otherwise gray out.
    New-Item -Path $HwReqChkPath -Force | Out-Null
    New-ItemProperty -Path $HwReqChkPath -Name 'HwReqChkVars' -PropertyType MultiString -Force -Value @(
        'SQ_SecureBootCapable=TRUE'
        'SQ_SecureBootEnabled=TRUE'
        'SQ_TpmVersion=2'
        'SQ_RamMB=8192'
    ) | Out-Null

    New-Item -Path $PchcPath -Force | Out-Null
    Set-ItemProperty $PchcPath -Name 'UpgradeEligibility' -Value 1 -Type DWord

    foreach ($p in $CompatStalePaths) { Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue }

    Log 'Bypass registry keys applied successfully (LabConfig, MoSetup, HwReqChk, PCHC).'
}

function Reset-Bypass {
    Log 'Removing bypass registry keys...'

    foreach ($n in $LabConfigValues) {
        Remove-ItemProperty -Path $LabConfigPath -Name $n -ErrorAction SilentlyContinue
    }
    Remove-ItemProperty -Path $MoSetupPath  -Name 'AllowUpgradesWithUnsupportedTPMOrCPU' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $HwReqChkPath -Name 'HwReqChkVars'       -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $PchcPath     -Name 'UpgradeEligibility' -ErrorAction SilentlyContinue

    # Only drop a key this script may not have created when it is left completely empty.
    foreach ($p in @($LabConfigPath, $HwReqChkPath)) {
        try {
            $k = Get-Item -Path $p -ErrorAction SilentlyContinue
            if ($k -and $k.ValueCount -eq 0 -and $k.SubKeyCount -eq 0) {
                Remove-Item -Path $p -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    Log 'Bypass keys reset.'
}

# ===================== ISO handling =====================

function Copy-IsoContent {
    param([string]$Source, [string]$Destination, [long]$TotalBytes)

    $win = New-T2FWindow -Title 'Extracting Windows 11 files' -Subtitle 'This can take several minutes on a slow drive.' -Width 660
    $win.Form.ControlBox = $false

    $bar = New-T2FProgress -Width 580 -Height 14
    $bar.Tag.Value = 0
    $win.Body.Controls.Add($bar)

    $pct = New-T2FText -Text 'Preparing...' -Size 15 -Color $C.Text -Weight 'Semibold' -MaxWidth 560
    $win.Body.Controls.Add($pct)
    $detail = New-T2FText -Text '' -Size 9.5 -MaxWidth 560
    $win.Body.Controls.Add($detail)

    $win.Form.ClientSize = New-Object System.Drawing.Size(660, 320)
    $win.Form.Show()
    [System.Windows.Forms.Application]::DoEvents()

    # The progress window must close even on failure, or it would stay open next to
    # the error dialog.
    try {
        $srcTrimmed = $Source.TrimEnd([char]92)
        $dstTrimmed = $Destination.TrimEnd([char]92)
        $rcArgs = '"{0}" "{1}" /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /MT:8' -f $srcTrimmed, $dstTrimmed
        Log "robocopy $rcArgs"
        $proc = Start-Process -FilePath 'robocopy.exe' -ArgumentList $rcArgs -WindowStyle Hidden -PassThru

        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 900
            $copied = 0
            try {
                $copied = (Get-ChildItem -LiteralPath $Destination -Recurse -Force -File -ErrorAction SilentlyContinue |
                           Measure-Object -Property Length -Sum).Sum
            } catch {}
            if (-not $copied) { $copied = 0 }

            $p = 0
            if ($TotalBytes -gt 0) { $p = [Math]::Min(99, [Math]::Floor(($copied / $TotalBytes) * 100)) }
            $bar.Tag.Value = $p
            $bar.Invalidate()
            $pct.Text    = "$p%"
            $detail.Text = '{0} of {1} copied' -f (Format-Size $copied), (Format-Size $TotalBytes)
            Write-Progress -Activity 'Extracting Windows 11 files' -Status ('{0}%  ({1} of {2})' -f $p, (Format-Size $copied), (Format-Size $TotalBytes)) -PercentComplete ([int]$p)
            [System.Windows.Forms.Application]::DoEvents()
        }

        $proc.WaitForExit()
        $bar.Tag.Value = 100
        $bar.Invalidate()
    } finally {
        Write-Progress -Activity 'Extracting Windows 11 files' -Completed
        $win.Form.Close()
        $win.Form.Dispose()
    }

    # robocopy uses 0-7 for success variants; 8 and above are real failures.
    # The folder is not deleted automatically because it may have existed before.
    if ($proc.ExitCode -ge 8) {
        throw ("Extraction failed (robocopy exit code $($proc.ExitCode)). " +
               "The partly copied files are in $Destination and can be deleted.")
    }
    Log "Extraction completed to $Destination (robocopy exit code $($proc.ExitCode))."
}

function Dismount-IsoSafely {
    if ($script:MountedIsoPath) {
        try {
            Dismount-DiskImage -ImagePath $script:MountedIsoPath -ErrorAction SilentlyContinue | Out-Null
            Log "Dismounted ISO: $script:MountedIsoPath"
        } catch {}
        $script:MountedIsoPath = $null
    }
}

# ===================== Screens =====================

$RepoUrl = 'https://github.com/tips2fix/Tips2Fix-Windows11-Installer'

# Plain-language explanation of what the tool does, what it never does, and where
# it stands with Microsoft. Deliberately makes no legal promises: it says what the
# tool does and lets the reader judge.
function Show-T2FAbout {
    $nl  = [Environment]::NewLine
    $win = New-T2FWindow -Title 'About this tool' -Subtitle 'What Tips2Fix does to your PC, in plain words.' -NoAbout

    $win.Body.Controls.Add((New-T2FText -Text ('Tips2Fix guides you through moving an older PC to Windows 11. It looks at your system, tells you which ' +
        'file to get from Microsoft, and starts Microsoft''s own Windows Setup. Windows itself is installed by Microsoft''s Setup, not by this tool.') -Size 10 -Color $C.Text))

    $c1 = New-T2FCard
    $c1.Controls.Add((New-T2FText -Text 'What it does, step by step' -Size 10.5 -Color $C.Text -Weight 'Semibold' -MaxWidth $UI.Inner))
    $c1.Controls.Add((New-T2FText -Text ("1. Reads your Windows version, edition, language and processor features. Nothing leaves your PC.$nl" +
        "2. Shows which Windows file you need, so your files and apps can be kept.$nl" +
        "3. Sets a few Windows settings that tell Setup to skip its hardware checks. It asks first.$nl" +
        "4. Starts Microsoft's Setup from the ISO you picked, or installs Microsoft's small enablement package.$nl" +
        '5. Writes everything it did to a log file in a Logs folder next to the tool, one file per run.') -Size 9.5 -MaxWidth $UI.Inner))
    $win.Body.Controls.Add($c1)

    $c2 = New-T2FCard
    $c2.Controls.Add((New-T2FText -Text 'What it can change on your PC (always after you agree)' -Size 10.5 -Color $C.Text -Weight 'Semibold' -MaxWidth $UI.Inner))
    $c2.Controls.Add((New-T2FText -Text ("Registry values under LabConfig, MoSetup, HwReqChk and PCHC. These are the settings Setup reads. You can remove them any time with Undo.$nl" +
        "The EFI boot fonts folder, only if you choose the reserved partition fix.$nl" +
        'A temporary drive for your ISO, removed again when the tool closes.') -Size 9.5 -MaxWidth $UI.Inner))
    $win.Body.Controls.Add($c2)

    $c3 = New-T2FCard -Accent $C.Ok -Fill $C.OkSoft
    $c3.Controls.Add((New-T2FText -Text 'What it never does' -Size 10.5 -Color $C.Ok -Weight 'Semibold' -MaxWidth $UI.Inner))
    $c3.Controls.Add((New-T2FText -Text ("It does not activate Windows or touch your license.$nl" +
        "It does not change, replace or patch any Windows file.$nl" +
        "It does not install other software, add startup items or run in the background.$nl" +
        "It does not collect or send any data, and it downloads nothing by itself. Links open Microsoft's own pages in your browser, after you say yes.") -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner))
    $win.Body.Controls.Add($c3)

    $c4 = New-T2FCard -Accent $C.Warn -Fill $C.WarnSoft
    $c4.Controls.Add((New-T2FText -Text 'Where this stands with Microsoft' -Size 10.5 -Color $C.Warn -Weight 'Semibold' -MaxWidth $UI.Inner))
    $c4.Controls.Add((New-T2FText -Text ('Microsoft''s own Setup reads these settings, and Microsoft lets you install Windows 11 on a PC that does not meet ' +
        'the requirements. It does not recommend it, it says such a PC is not guaranteed to receive updates, and it offers no support for it. ' +
        'You still need a valid Windows license. This is a description of how the tool works, not legal advice, and you stay responsible for your PC and your license.') -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner))
    $win.Body.Controls.Add($c4)

    $c5 = New-T2FCard
    $c5.Controls.Add((New-T2FText -Text 'Open source, so you can check' -Size 10.5 -Color $C.Text -Weight 'Semibold' -MaxWidth $UI.Inner))
    $c5.Controls.Add((New-T2FText -Text ('Every line is readable on GitHub under the MIT license, and the standalone patcher is a short plain batch file. ' +
        'Nothing is hidden or encoded.') -Size 9.5 -MaxWidth $UI.Inner))
    $row = New-T2FButtonRow -Fill $C.Surface
    $btnRepo = New-T2FButton -Text 'View on GitHub'
    $btnLog  = New-T2FButton -Text 'Open this run''s log'
    $btnDir  = New-T2FButton -Text 'Open logs folder'
    $btnRepo.Add_Click({ Open-T2FDownload -Title 'Open your web browser?' -What 'the Tips2Fix page on GitHub' -Url $RepoUrl })
    $btnLog.Add_Click({
        if ($logPath -and (Test-Path -LiteralPath $logPath)) {
            try { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $logPath + '"') | Out-Null }
            catch { Log "Could not open the log: $($_.Exception.Message)" }
        }
    })
    $btnDir.Add_Click({
        if ($logPath -and (Test-Path -LiteralPath $logPath)) {
            try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $logPath + '"') | Out-Null }
            catch { Log "Could not open the logs folder: $($_.Exception.Message)" }
        }
    })
    $row.Controls.Add($btnRepo)
    $row.Controls.Add($btnLog)
    $row.Controls.Add($btnDir)
    $c5.Controls.Add($row)
    $win.Body.Controls.Add($c5)

    $btnClose = New-T2FButton -Text 'Close' -Kind 'primary'
    $btnClose.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $win.Buttons.Controls.Add($btnClose)
    $win.Form.AcceptButton = $btnClose
    $win.Form.CancelButton = $btnClose

    Show-T2FWindow -Win $win | Out-Null
}

function Show-Welcome {
    $win = New-T2FWindow -Title "Windows 11 $TargetName Installer" -Subtitle 'Safe Confirmed Edition - by Tips2Fix'

    $win.Body.Controls.Add((New-T2FHeading -Text 'Install Windows 11 on an unsupported PC'))
    $win.Body.Controls.Add((New-T2FText -Text ("This tool guides you through upgrading to Windows 11 $TargetName, step by step. " +
        'Every action that changes your system asks for your permission first, and everything it does is written to a log file in a Logs folder next to the tool.') -Size 10 -Color $C.Text))

    $card = New-T2FCard -Accent $C.Warn -Fill $C.WarnSoft
    $card.Controls.Add((New-T2FText -Text 'Back up your files before you continue' -Size 10.5 -Color $C.Warn -Weight 'Semibold' -MaxWidth $UI.Inner))
    $card.Controls.Add((New-T2FText -Text ('Installing Windows on unsupported hardware is done at your own risk. Microsoft does not guarantee ' +
        'updates, drivers or support for this configuration. By continuing you confirm that you understand and accept this.') -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner))
    $win.Body.Controls.Add($card)

    $win.Body.Controls.Add((New-T2FText -Text 'Nothing is installed or changed until you approve each step.' -Size 9.5))

    $btnExit = New-T2FButton -Text 'Exit' -Kind 'quiet'
    $btnGo   = New-T2FButton -Text 'I understand, continue' -Kind 'primary'
    $btnGo.DialogResult   = [System.Windows.Forms.DialogResult]::OK
    $btnExit.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $win.Buttons.Controls.Add($btnGo)
    $win.Buttons.Controls.Add($btnExit)
    $win.Form.AcceptButton = $btnGo

    if ((Show-T2FWindow -Win $win) -eq [System.Windows.Forms.DialogResult]::OK) { return 'next' }
    return 'exit'
}

function Show-SystemScan {
    param($Os, $Inst, $Sse, $Hw)

    $win = New-T2FWindow -Title 'Your system' -Subtitle 'Checked before anything is changed.'

    $win.Body.Controls.Add((New-T2FHeading -Text 'What this PC is running'))
    $card = New-T2FCard
    $card.Controls.Add((New-T2FStatusRow -Label 'Windows version' -Value $Os.Friendly -State 'info'))
    $card.Controls.Add((New-T2FStatusRow -Label 'Edition'         -Value ("Windows " + $(if ($Os.IsWin10) { '10' } else { '11' }) + " $($Inst.Edition)") -State 'info'))
    $card.Controls.Add((New-T2FStatusRow -Label 'Language'        -Value "$($Inst.LanguageName)  [$($Inst.LanguageTag)]" -State 'info'))
    $card.Controls.Add((New-T2FStatusRow -Label 'Architecture'    -Value $Inst.Architecture -State 'info'))
    $win.Body.Controls.Add($card)

    if ($Hw) {
        $win.Body.Controls.Add((New-T2FHeading -Text 'Your hardware against Windows 11''s minimum'))
        $sum   = Get-HardwareSummary -Rows $Hw.Rows -Sse $Sse
        $hwCard = New-T2FCard -Accent $(switch ($sum.State) { 'err' { $C.Err } 'warn' { $C.Warn } default { $C.Ok } }) `
                              -Fill   $(switch ($sum.State) { 'err' { $C.ErrSoft } 'warn' { $C.WarnSoft } default { $C.OkSoft } })
        foreach ($r in $Hw.Rows) {
            $hwCard.Controls.Add((New-T2FStatusRow -Label $r.Label -Value $r.Value -State $r.State -Width $UI.Inner))
        }
        $hwCard.Controls.Add((New-T2FText -Text $sum.Text -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner))
        $win.Body.Controls.Add($hwCard)
    }

    $win.Body.Controls.Add((New-T2FHeading -Text 'The requirement that cannot be bypassed'))

    if ($Sse.Supported -eq $true) {
        $c2 = New-T2FCard -Accent $C.Ok -Fill $C.OkSoft
        $c2.Controls.Add((New-T2FStatusRow -Label 'SSE4.2 / POPCNT' -Value 'Supported' -State 'ok' -Width $UI.Inner))
        $c2.Controls.Add((New-T2FText -Text ('Your processor clears the only hardware requirement no tool can work around. ' +
            'TPM, Secure Boot, RAM and the supported-CPU list can all be bypassed from here.') -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner))
        $win.Body.Controls.Add($c2)
    } elseif ($Sse.Supported -eq $false) {
        $c2 = New-T2FCard -Accent $C.Err -Fill $C.ErrSoft
        $c2.Controls.Add((New-T2FStatusRow -Label 'SSE4.2 / POPCNT' -Value 'Not supported' -State 'err' -Width $UI.Inner))
        $c2.Controls.Add((New-T2FText -Text ("Windows 11 $TargetName will not boot on this processor, even if Setup finishes. " +
            'This is enforced by the Windows kernel itself, so no registry key or installer trick changes it. ' +
            'Windows 11 23H2 is the newest version this PC can run.') -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner))
        $win.Body.Controls.Add($c2)
    } else {
        $c2 = New-T2FCard -Accent $C.Warn -Fill $C.WarnSoft
        $c2.Controls.Add((New-T2FStatusRow -Label 'SSE4.2 / POPCNT' -Value 'Could not be confirmed' -State 'warn' -Width $UI.Inner))
        $c2.Controls.Add((New-T2FText -Text 'Verify with CPU-Z or Coreinfo before continuing.' -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner))
        $c2.Controls.Add((New-T2FLink -Text 'Download CPU-Z'    -Url $CpuZUrl))
        $c2.Controls.Add((New-T2FLink -Text 'Download Coreinfo' -Url $CoreinfoUrl))
        $c2.Controls.Add((New-T2FLink -Text 'Step-by-step guide on Tips2Fix' -Url $BlogSse42Url))
        $win.Body.Controls.Add($c2)
    }

    $win.Body.Controls.Add((New-T2FText -Text ("Detected using: " + $Sse.Method) -Size 9))

    $ph = New-T2FCard
    $ph.Controls.Add((New-T2FText -Text 'Want to see what Microsoft says about this PC?' -Size 10.5 -Color $C.Text -Weight 'Semibold' -MaxWidth $UI.Inner))
    $ph.Controls.Add((New-T2FText -Text ('PC Health Check is Microsoft''s own app that reports whether a PC meets the official Windows 11 requirements. ' +
        'On an unsupported PC it will say no. That is expected: it only reports, and it does not stop this tool.') -Size 9.5 -MaxWidth $UI.Inner))
    $phRow = New-T2FButtonRow -Fill $C.Surface
    $btnPh  = New-T2FButton -Text 'Download PC Health Check'
    $btnPhS = New-T2FButton -Text 'Microsoft support page'
    $btnPh.Add_Click({  Open-T2FDownload -Title 'Open your web browser?' -What 'the PC Health Check download from Microsoft (about 14 MB)' -Url $PcHealthUrl })
    $btnPhS.Add_Click({ Open-T2FDownload -Title 'Open your web browser?' -What 'the Microsoft support page for PC Health Check' -Url $PcHealthSupportUrl })
    $phRow.Controls.Add($btnPh)
    $phRow.Controls.Add($btnPhS)
    $ph.Controls.Add($phRow)
    $win.Body.Controls.Add($ph)

    $script:ScanNav = 'exit'
    $btnBack = New-T2FButton -Text 'Back' -Kind 'quiet'
    $btnNext = New-T2FButton -Text 'Continue' -Kind 'primary'
    $btnBack.Add_Click({ $script:ScanNav = 'back'; $win.Form.Close() })
    $btnNext.Add_Click({ $script:ScanNav = 'next'; $win.Form.Close() })
    $win.Buttons.Controls.Add($btnNext)
    $win.Buttons.Controls.Add($btnBack)
    $win.Form.AcceptButton = $btnNext

    Show-T2FWindow -Win $win | Out-Null
    return $script:ScanNav
}

# Tells the user exactly which ISO to download before offering to open the
# Microsoft page, because the wrong language or edition is what silently costs
# people their installed programs.
function Show-IsoRequirements {
    param($Inst)

    $win = New-T2FWindow -Title 'Which ISO do you need?' -Subtitle 'Downloading the wrong one is the usual reason people lose their apps.'

    $win.Body.Controls.Add((New-T2FHeading -Text 'Download exactly this'))
    $win.Body.Controls.Add((New-T2FText -Text ('Windows Setup only offers to keep your files and apps when the installation media matches ' +
        'what is already on this PC. Match every line below on the Microsoft download page.') -Size 10 -Color $C.Text))

    $card = New-T2FCard -Accent $C.Accent -Fill $C.AccentSoft
    $card.Controls.Add((New-T2FStatusRow -Label 'Product'      -Value "Windows 11 $TargetName" -State 'ok' -Width $UI.Inner))
    $card.Controls.Add((New-T2FStatusRow -Label 'Edition'      -Value $Inst.Edition            -State 'ok' -Width $UI.Inner))
    $card.Controls.Add((New-T2FStatusRow -Label 'Language'     -Value $Inst.LanguageName       -State 'ok' -Width $UI.Inner))
    $card.Controls.Add((New-T2FStatusRow -Label 'Architecture' -Value $Inst.Architecture       -State 'ok' -Width $UI.Inner))
    $win.Body.Controls.Add($card)

    $warn = New-T2FCard -Accent $C.Warn -Fill $C.WarnSoft
    $warn.Controls.Add((New-T2FText -Text 'If you pick a different language or edition' -Size 10 -Color $C.Warn -Weight 'Semibold' -MaxWidth $UI.Inner))
    $warn.Controls.Add((New-T2FText -Text ('Setup will gray out "Keep personal files and apps" and the only option left will be a clean install, ' +
        'which removes every program on this PC. The language must match exactly: "English (United States)" and ' +
        '"English (United Kingdom)" count as different.') -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner))
    $win.Body.Controls.Add($warn)

    # Step 1: get the file. The browser opens beside this window, which stays open.
    $step1 = New-T2FCard
    $step1.Controls.Add((New-T2FText -Text 'Do not have the ISO yet?' -Size 10.5 -Color $C.Text -Weight 'Semibold' -MaxWidth $UI.Inner))
    $step1.Controls.Add((New-T2FText -Text ('Open the Microsoft download page, choose "Windows 11 Disk Image (ISO)" and pick the language ' +
        'listed above. The file is about 7.9 GB. This window stays open while you download.') -Size 9.5 -MaxWidth $UI.Inner))

    $row1 = New-T2FButtonRow -Fill $C.Surface
    $btnOpen = New-T2FButton -Text 'Open download page'
    $btnCopy = New-T2FButton -Text 'Copy details'
    $row1.Controls.Add($btnOpen)
    $row1.Controls.Add($btnCopy)
    $step1.Controls.Add($row1)

    $hint = New-T2FText -Text '' -Size 9.5 -MaxWidth $UI.Inner
    $hint.Visible = $false
    $step1.Controls.Add($hint)
    $win.Body.Controls.Add($step1)

    $win.Body.Controls.Add((New-T2FText -Text ('When the download finishes, or if you already have the ISO on this PC, ' +
        'click "Select ISO from PC" below.') -Size 10 -Color $C.Text))

    $script:IsoReq = @{ Action = 'back'; Path = $null }

    $btnOpen.Add_Click({
        Open-T2FDownload -Title 'Open your web browser?' -What 'the official Microsoft Windows 11 download page' `
                         -Url $IsoDownloadUrl -Hint $hint
    })

    $btnCopy.Add_Click({
        $nl = [Environment]::NewLine
        $text = "Windows 11 $TargetName$nl" +
                "Edition: $($Inst.Edition)$nl" +
                "Language: $($Inst.LanguageName)$nl" +
                "Architecture: $($Inst.Architecture)"
        try {
            [System.Windows.Forms.Clipboard]::SetText($text)
            Log 'Copied ISO requirements to clipboard.'
            $this.Text = 'Copied'
            $this.Invalidate()
        } catch { Log "Clipboard unavailable: $($_.Exception.Message)" }
    })

    $btnBack = New-T2FButton -Text 'Back' -Kind 'quiet'
    $btnPick = New-T2FButton -Text 'Select ISO from PC' -Kind 'primary'

    $btnBack.Add_Click({ $script:IsoReq.Action = 'back'; $win.Form.Close() })
    $btnPick.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'ISO files (*.iso)|*.iso'
        $ofd.Title  = "Select your Windows 11 $TargetName ISO"
        # Cancelling the picker returns to this window instead of ending the flow.
        if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:IsoReq.Action = 'selected'
            $script:IsoReq.Path   = $ofd.FileName
            $win.Form.Close()
        }
    })

    $win.Buttons.Controls.Add($btnPick)
    $win.Buttons.Controls.Add($btnBack)
    $win.Form.AcceptButton = $btnPick

    Show-T2FWindow -Win $win | Out-Null
    return $script:IsoReq
}

function Show-ModeSelection {
    param($Os)

    $script:ChoiceGroup = @()
    $win = New-T2FWindow -Title 'Choose how to upgrade' -Subtitle "Detected: $($Os.Friendly)"

    if ($Os.IsWin10) {
        $note = New-T2FCard -Accent $C.Accent -Fill $C.AccentSoft
        $note.Controls.Add((New-T2FText -Text 'Windows 10 support ended on 14 October 2025' -Size 10 -Color $C.AccentDeep -Weight 'Semibold' -MaxWidth $UI.Inner))
        $note.Controls.Add((New-T2FText -Text ("This PC no longer receives security updates. You can go straight to Windows 11 $TargetName " +
            'and keep your files and apps, as long as the ISO matches your edition and language. This tool checks that for you.') -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner))
        $win.Body.Controls.Add($note)
    }

    $ekbDesc = if ($Os.EkbCapable) {
        "A $EkbKb package of about 174 KB. No ISO, no hardware check, one restart. The safest route on unsupported hardware."
    } else {
        "Not available here. This route needs Windows 11 24H2 or 25H2, and you are on $($Os.Friendly)."
    }
    $cEkb = New-T2FChoice -Title 'Fast update (enablement package)' -Description $ekbDesc `
                          -IsChecked $Os.EkbCapable -IsEnabled $Os.EkbCapable `
                          -Badge $(if ($Os.EkbCapable) { 'RECOMMENDED' } else { '' })
    $win.Body.Controls.Add($cEkb)

    $isoDesc = if ($Os.IsWin10) {
        'Applies the bypass keys, checks that your ISO matches this PC, then runs Windows Setup so you keep your files and apps.'
    } else {
        'Applies the bypass keys with your permission, then runs Windows Setup from a Windows 11 ISO.'
    }
    $cIso = New-T2FChoice -Title 'Install from a Windows 11 ISO' -Description $isoDesc `
                          -IsChecked (-not $Os.EkbCapable) `
                          -Badge $(if ($Os.IsWin10) { 'RECOMMENDED' } else { '' })
    $win.Body.Controls.Add($cIso)

    $win.Body.Controls.Add((New-T2FHeading -Text 'Or just use one tool' -Size 11))

    $cApply = New-T2FChoice -Title 'Apply the requirement bypass only' `
        -Description 'Writes the bypass values and stops, so you can run Setup yourself later. Nothing else happens.'
    $win.Body.Controls.Add($cApply)

    $cReset = New-T2FChoice -Title 'Undo the bypass' `
        -Description 'Removes every registry value the bypass added and restores the defaults.'
    $win.Body.Controls.Add($cReset)

    $cEfi = New-T2FChoice -Title 'Fix "We couldn''t update the system reserved partition"' `
        -Description 'Clears the small EFI boot partition so Setup can finish. Use it if you hit that error right after clicking Next.'
    $win.Body.Controls.Add($cEfi)

    $script:ModeNav = 'exit'
    $btnBack = New-T2FButton -Text 'Back' -Kind 'quiet'
    $btnNext = New-T2FButton -Text 'Continue' -Kind 'primary'
    $btnBack.Add_Click({ $script:ModeNav = 'back'; $win.Form.Close() })
    $btnNext.Add_Click({ $script:ModeNav = 'next'; $win.Form.Close() })
    $win.Buttons.Controls.Add($btnNext)
    $win.Buttons.Controls.Add($btnBack)
    $win.Form.AcceptButton = $btnNext

    Show-T2FWindow -Win $win | Out-Null
    if ($script:ModeNav -ne 'next') { return $script:ModeNav }
    if ($cEkb.Tag.Checked)   { return 'ekb' }
    if ($cApply.Tag.Checked) { return 'apply' }
    if ($cReset.Tag.Checked) { return 'reset' }
    if ($cEfi.Tag.Checked)   { return 'efi' }
    return 'iso'
}

function Show-UpgradePreflight {
    param([string]$IsoRoot, $Inst)

    Write-Host 'Checking that the ISO matches this installation...' -ForegroundColor Cyan
    $isoLangs = Get-IsoLanguages -Root $IsoRoot
    $isoEds   = Get-IsoEditions  -Root $IsoRoot

    $langOk = ($isoLangs.Count -eq 0) -or ($isoLangs -contains $Inst.LanguageTag)
    $edOk   = ($isoEds.Count   -eq 0) -or [bool]($isoEds | Where-Object { $_ -match ([regex]::Escape($Inst.Edition) + '$') })

    $sysFree = Get-FreeSpaceBytes -Path $env:SystemDrive
    $spaceOk = ($sysFree -lt 0) -or ($sysFree -ge $UpgradeFreeSpaceBytes)

    Log ("Preflight | installed: $($Inst.Edition) $($Inst.LanguageTag) | iso languages: $($isoLangs -join ',') | " +
         "iso editions: $($isoEds -join ' / ') | langOk=$langOk edOk=$edOk free=$(Format-Size $sysFree)")

    $allOk = $langOk -and $edOk -and $spaceOk
    $win = New-T2FWindow -Title $(if ($allOk) { 'Your ISO matches' } else { 'This ISO may cost you your apps' }) `
                         -Subtitle $(if ($allOk) { 'Everything lines up for an in-place upgrade.' } else { 'Read this before continuing.' })

    $card = New-T2FCard -Accent $(if ($allOk) { $C.Ok } else { $C.Warn }) -Fill $(if ($allOk) { $C.OkSoft } else { $C.WarnSoft })
    $card.Controls.Add((New-T2FStatusRow -Label 'Language' -State $(if ($langOk) { 'ok' } else { 'err' }) -Width $UI.Inner `
        -Value $(if ($langOk) { "Matches ($($Inst.LanguageTag))" } else { "$($Inst.LanguageTag) needed, ISO has $($isoLangs -join ', ')" })))
    $card.Controls.Add((New-T2FStatusRow -Label 'Edition' -State $(if ($edOk) { 'ok' } else { 'err' }) -Width $UI.Inner `
        -Value $(if ($edOk) { "Matches ($($Inst.Edition))" } else { "$($Inst.Edition) needed, ISO has $($isoEds -join ', ')" })))
    $card.Controls.Add((New-T2FStatusRow -Label 'Free space' -State $(if ($spaceOk) { 'ok' } else { 'err' }) -Width $UI.Inner `
        -Value $(if ($spaceOk) { "$(Format-Size $sysFree) available" } else { "$(Format-Size $sysFree) free, about $(Format-Size $UpgradeFreeSpaceBytes) needed" })))
    $win.Body.Controls.Add($card)

    if ($allOk) {
        $win.Body.Controls.Add((New-T2FText -Text 'Windows Setup will offer to keep your personal files and apps.' -Size 10 -Color $C.Text))
    } else {
        $win.Body.Controls.Add((New-T2FText -Text ('With a mismatch, Setup normally grays out "Keep personal files and apps" and the only ' +
            'remaining option removes your installed programs. Downloading the matching ISO is almost always worth the wait.') -Size 10 -Color $C.Text))
    }

    $script:PreflightNav = 'back'
    $btnBack = New-T2FButton -Text 'Choose another ISO' -Kind 'quiet'
    $btnGo   = New-T2FButton -Text $(if ($allOk) { 'Continue' } else { 'Continue anyway' }) -Kind $(if ($allOk) { 'primary' } else { 'danger' })
    $btnBack.Add_Click({ $script:PreflightNav = 'back'; $win.Form.Close() })
    $btnGo.Add_Click({   $script:PreflightNav = 'next'; $win.Form.Close() })
    $win.Buttons.Controls.Add($btnGo)
    $win.Buttons.Controls.Add($btnBack)
    if ($allOk) { $win.Form.AcceptButton = $btnGo }

    Show-T2FWindow -Win $win | Out-Null
    Log "Preflight result allOk=$allOk; user chose $($script:PreflightNav)"
    return $script:PreflightNav
}

function Show-SetupMonitor {
    $script:RetryFallback = $false
    $win = New-T2FWindow -Title 'Windows Setup is running' -Subtitle 'Follow the Windows Setup window that just opened.'

    $card = New-T2FCard -Accent $C.Ok -Fill $C.OkSoft
    $status = New-T2FStatusRow -Label 'Setup' -Value 'Running' -State 'ok' -Width $UI.Inner
    $card.Controls.Add($status)
    $win.Body.Controls.Add($card)

    $win.Body.Controls.Add((New-T2FText -Text ('When Setup asks what to keep, choose "Keep personal files and apps". ' +
        'You can close this window once the installation starts copying files.') -Size 10 -Color $C.Text))

    $fb = New-T2FCard -Accent $C.Warn -Fill $C.WarnSoft
    $fb.Controls.Add((New-T2FText -Text 'Only if Setup refuses to start' -Size 10 -Color $C.Warn -Weight 'Semibold' -MaxWidth $UI.Inner))
    $fb.Controls.Add((New-T2FText -Text ('There is a second method that skips more checks, but it normally grays out ' +
        '"Keep personal files and apps", which means your programs would be removed. Use it only if the normal method was blocked.') -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner))
    $win.Body.Controls.Add($fb)

    $btnClose = New-T2FButton -Text 'Close' -Kind 'primary'
    $btnRetry = New-T2FButton -Text 'Setup was blocked - retry'
    $btnClose.Add_Click({ $win.Form.Close() })
    $btnRetry.Add_Click({
        $ok = Confirm-T2F -Title 'Retry with the fallback method?' -State 'warn' `
                -Message 'This relaunches Setup through the Windows Server compatibility path.' `
                -Detail ('It normally grays out "Keep personal files and apps". If Setup then offers only "Nothing", ' +
                         'your installed programs will be removed. Cancel Setup if you are not ready for that.') `
                -YesText 'Retry anyway' -NoText 'Go back'
        if ($ok) { $script:RetryFallback = $true; $win.Form.Close() }
    })
    $win.Buttons.Controls.Add($btnClose)
    $win.Buttons.Controls.Add($btnRetry)

    # Windows Setup rejects an unsupported PC within the first few minutes, so an
    # early exit is the signal that the fallback is worth offering.
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 4000
    $timer.Add_Tick({
        try {
            if ($script:SetupProc -and $script:SetupProc.HasExited) {
                $timer.Stop()
                $status.ValueLabel.Text      = 'Closed earlier than expected'
                $status.ValueLabel.ForeColor = $C.Err
                $status.IconLabel.Text       = [string]$G.Warning
                $status.IconLabel.ForeColor  = $C.Err
            }
        } catch {}
    })
    $timer.Start()

    Show-T2FWindow -Win $win | Out-Null
    $timer.Stop(); $timer.Dispose()
    return $script:RetryFallback
}

# ===================== Flows =====================

function Start-WindowsSetup {
    param([string]$SetupPath, [switch]$ServerFallback)
    $workDir = Split-Path -Parent $SetupPath
    $argLine = '/compat ignorewarning /dynamicupdate disable /migratedrivers all'
    if ($ServerFallback) { $argLine = '/product server ' + $argLine }
    Log "Launching setup: $SetupPath $argLine"
    return (Start-Process -FilePath $SetupPath -ArgumentList $argLine -WorkingDirectory $workDir -PassThru)
}

function Invoke-SetupFlow {
    param([string]$SetupPath)
    $script:SetupProc = Start-WindowsSetup -SetupPath $SetupPath
    Write-Host 'Windows 11 Setup launched.' -ForegroundColor Green

    if (Show-SetupMonitor) {
        Log 'User requested the /product server fallback.'
        Write-Host 'Retrying Setup with the compatibility fallback...' -ForegroundColor Yellow
        $script:SetupProc = Start-WindowsSetup -SetupPath $SetupPath -ServerFallback
        Show-SetupMonitor | Out-Null
    }
}

# Opens a download link in the browser after asking, and leaves the caller's window open.
function Open-T2FDownload {
    param([string]$Title, [string]$What, [string]$Url, $Hint)

    $nl = [Environment]::NewLine
    $ok = Confirm-T2F -Title $Title `
            -Message "Tips2Fix would like to open $What in your default browser." `
            -Detail ("Address: $Url$nl$nl" +
                     'The download is handled by your browser, and this installer window stays open.') `
            -YesText 'Open browser' -NoText 'Not now' -CopyText $Url
    if (-not $ok) { Log "User declined to open: $Url"; return }

    try {
        Start-Process $Url | Out-Null
        Log "Opened: $Url"
        if ($Hint) {
            $Hint.Text      = 'Browser opened. Leave this window where it is, and come back when the download finishes.'
            $Hint.ForeColor = $C.Ok
            $Hint.Visible   = $true
        }
    } catch {
        Log "Could not open browser for $Url : $($_.Exception.Message)"
        if ($Hint) {
            $Hint.Text      = 'The browser could not be opened. The address is in the log file.'
            $Hint.ForeColor = $C.Err
            $Hint.Visible   = $true
        }
    }
}

function Invoke-EkbFlow {
    param($Os, $Inst)

    $nl = [Environment]::NewLine
    Log "Enablement package path selected (current build $($Os.Build).$($Os.UBR))."

    $isArm     = ($Inst.Architecture -eq 'ARM64')
    $prereqOk  = ([int]$Os.UBR -ge $EkbPrereqUbr)
    Log "Prerequisite $EkbPrereqKb present: $prereqOk (UBR $($Os.UBR), needs $EkbPrereqUbr or higher)"

    $win = New-T2FWindow -Title "Fast update to Windows 11 $TargetName" -Subtitle 'No ISO needed on this PC.'

    $win.Body.Controls.Add((New-T2FText -Text ("You are running $($Os.Friendly). Windows 11 $TargetName is built on the same core, so it " +
        'arrives as a small enablement package instead of a full installation. No hardware check runs, and one restart finishes it.') -Size 10 -Color $C.Text))

    # --- Step 1: the prerequisite update
    # Built once and refreshed in place, so installing the prerequisite never means
    # restarting the tool.
    $c1 = New-T2FCard -Accent $C.Warn -Fill $C.WarnSoft
    $hdr1 = New-T2FStepHeader -Number 1 -Title "Required update $EkbPrereqKb" -State 'active'
    $hdr2 = New-T2FStepHeader -Number 2 -Title "Download $EkbKb" -State 'todo'
    $c1.Controls.Add($hdr1)
    $rowPrereq = New-T2FStatusRow -Label 'On this PC' -State 'warn' -Value 'Checking...'
    $c1.Controls.Add($rowPrereq)

    $txtPrereq = New-T2FText -Text '' -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner
    $c1.Controls.Add($txtPrereq)

    $hint1 = New-T2FText -Text '' -Size 9.5 -MaxWidth $UI.Inner
    $hint1.Visible = $false

    $row1 = New-T2FButtonRow -Fill $C.WarnSoft
    $btnPrereq    = New-T2FButton -Text "Download $EkbPrereqKb (x64)" -Kind $(if ($isArm) { 'secondary' } else { 'primary' })
    $btnPrereqCat = New-T2FButton -Text 'Open Update Catalog' -Kind $(if ($isArm) { 'primary' } else { 'secondary' })
    $btnPrereqChk = New-T2FButton -Text 'Check again'
    $btnPrereq.Enabled = (-not $isArm)
    $btnPrereq.Add_Click({
        Open-T2FDownload -Title 'Open your web browser?' -What "the x64 package for $EkbPrereqKb (about 4.3 GB)" `
                         -Url $EkbPrereqX64 -Hint $hint1
    })
    $btnPrereqCat.Add_Click({
        Open-T2FDownload -Title 'Open your web browser?' -What "the Microsoft Update Catalog page for $EkbPrereqKb" `
                         -Url $EkbPrereqUrl -Hint $hint1
    })
    $row1.Controls.Add($btnPrereq)
    $row1.Controls.Add($btnPrereqCat)
    $row1.Controls.Add($btnPrereqChk)
    $c1.Controls.Add($row1)

    $noteArch = New-T2FText -Text $(if ($isArm) {
            'The direct link is x64 only, so use the Update Catalog and pick the ARM64 file.'
        } else {
            'This one is a full cumulative update, so it is about 4.3 GB. Use the catalog if you want to pick a different build.'
        }) -Size 9 -MaxWidth $UI.Inner
    $c1.Controls.Add($noteArch)
    $c1.Controls.Add($hint1)
    $win.Body.Controls.Add($c1)

    # Re-reads the build number and repaints the card, so the user can install the
    # prerequisite and carry on in the same window.
    $refreshPrereq = {
        $now = Get-OsInfo
        $ok  = ([int]$now.UBR -ge $EkbPrereqUbr)
        $script:EkbPrereqOk = $ok

        $rowPrereq.ValueLabel.Text      = $(if ($ok) { "Installed (build $($now.Build).$($now.UBR))" } else { "Missing (build $($now.Build).$($now.UBR))" })
        $rowPrereq.ValueLabel.ForeColor = $(if ($ok) { $C.Ok } else { $C.Warn })
        $rowPrereq.IconLabel.Text       = [string]$(if ($ok) { $G.Check } else { $G.Warning })
        $rowPrereq.IconLabel.ForeColor  = $(if ($ok) { $C.Ok } else { $C.Warn })

        # Step 1 turns into a tick once done, and step 2 becomes the one to do next.
        $hdr1.Tag.State = $(if ($ok) { 'done' } else { 'active' })
        $hdr2.Tag.State = $(if ($ok) { 'active' } else { 'todo' })
        $hdr1.Invalidate(); $hdr2.Invalidate()

        $c1.Tag       = $(if ($ok) { $C.Ok } else { $C.Warn })
        $c1.BackColor = $(if ($ok) { $C.OkSoft } else { $C.WarnSoft })
        foreach ($r in @($row1)) { $r.BackColor = $c1.BackColor }
        $c1.Invalidate()

        $txtPrereq.Text = $(if ($ok) {
            'Nothing to do here. Go on to step 2.'
        } else {
            "$EkbKb will not install until $EkbPrereqKb is on this PC. The quickest route is Windows Update. " +
            'You can also download it below and double-click the file. A restart is normally needed before Windows reports it as installed.'
        })

        $btnPrereq.Visible    = (-not $ok)
        $btnPrereqCat.Visible = (-not $ok)
        $btnPrereqChk.Visible = (-not $ok)
        $noteArch.Visible     = (-not $ok)
        if ($ok) { $hint1.Visible = $false }
    }

    $btnPrereqChk.Add_Click({
        & $refreshPrereq
        if (-not $script:EkbPrereqOk) {
            $hint1.Text      = "Still missing. If you just installed $EkbPrereqKb, restart this PC first and then run Tips2Fix again."
            $hint1.ForeColor = $C.Warn
            $hint1.Visible   = $true
        }
        Log "Re-checked $EkbPrereqKb : present = $($script:EkbPrereqOk)"
    })

    & $refreshPrereq

    # --- Step 2: the enablement package itself
    $c2 = New-T2FCard
    $c2.Controls.Add($hdr2)
    $c2.Controls.Add((New-T2FText -Text ('These are direct links to Microsoft servers. Your PC needs the ' +
        "$($Inst.Architecture) package, which is marked below.") -Size 9.5 -MaxWidth $UI.Inner))

    $hint2 = New-T2FText -Text '' -Size 9.5 -MaxWidth $UI.Inner
    $hint2.Visible = $false

    $row2 = New-T2FButtonRow -Fill $C.Surface
    $btnX64 = New-T2FButton -Text $(if ($isArm) { 'x64 (Intel / AMD)' } else { 'Download for Intel / AMD (x64)' }) `
                            -Kind $(if ($isArm) { 'secondary' } else { 'primary' })
    $btnArm = New-T2FButton -Text $(if ($isArm) { 'Download for ARM64' } else { 'ARM64' }) `
                            -Kind $(if ($isArm) { 'primary' } else { 'secondary' })
    $btnCat = New-T2FButton -Text 'Update Catalog'
    $btnX64.Add_Click({ Open-T2FDownload -Title 'Open your web browser?' -What "the x64 package for $EkbKb (about 173 KB)" -Url $EkbDirectX64 -Hint $hint2 })
    $btnArm.Add_Click({ Open-T2FDownload -Title 'Open your web browser?' -What "the ARM64 package for $EkbKb (about 175 KB)" -Url $EkbDirectArm64 -Hint $hint2 })
    $btnCat.Add_Click({ Open-T2FDownload -Title 'Open your web browser?' -What "the Microsoft Update Catalog page for $EkbKb" -Url $EkbCatalogUrl -Hint $hint2 })
    $row2.Controls.Add($btnX64)
    $row2.Controls.Add($btnArm)
    $row2.Controls.Add($btnCat)
    $c2.Controls.Add($row2)
    $c2.Controls.Add($hint2)
    $c2.Controls.Add((New-T2FText -Text ('Use "Update Catalog" if a direct link stops working. This tool downloads nothing by itself.') -Size 9 -MaxWidth $UI.Inner))
    $win.Body.Controls.Add($c2)

    # --- Step 3: install it. This is the call to action, so it is the strongest card
    # on the screen and holds its own button, progress bar and result.
    $c3 = New-T2FCard -Accent $C.Accent -Fill $C.AccentSoft
    $c3.Controls.Add((New-T2FStepHeader -Number 3 -Title 'Install the file you downloaded' -State 'active'))
    $c3.Controls.Add((New-T2FText -Text ("Click the orange button and pick a downloaded .msu file. It installs whichever one you pick, " +
        "so use it for $EkbPrereqKb first if step 1 says it is missing, and then for $EkbKb from step 2. " +
        'Progress is shown right here.') -Size 10 -Color $C.Text -MaxWidth $UI.Inner))

    $btnPick = New-T2FButton -Text 'Select .msu file and install' -Kind 'primary' -Width 280
    $row3 = New-T2FButtonRow -Fill $C.AccentSoft
    $row3.Controls.Add($btnPick)
    $c3.Controls.Add($row3)

    $progBar  = New-T2FProgress -Width $UI.Inner
    $progText = New-T2FText -Text '' -Size 10.5 -Color $C.Text -Weight 'Semibold' -MaxWidth $UI.Inner
    $progBar.Visible = $false; $progText.Visible = $false
    $c3.Controls.Add($progBar)
    $c3.Controls.Add($progText)

    $rowInstall = New-T2FStatusRow -Label 'Installation' -State 'info' -Value 'Not started yet'
    $c3.Controls.Add($rowInstall)
    $txtInstall = New-T2FText -Text '' -Size 9.5 -Color $C.Text -MaxWidth $UI.Inner
    $txtInstall.Visible = $false
    $c3.Controls.Add($txtInstall)
    $win.Body.Controls.Add($c3)

    $script:EkbResult = 'back'

    $btnBack    = New-T2FButton -Text 'Back' -Kind 'quiet'
    $btnRestart = New-T2FButton -Text 'Restart now' -Kind 'primary'
    $btnRestart.Visible = $false
    $script:EkbBusy = $false

    # Closing the window mid-install would leave DISM running with nothing on screen.
    $win.Form.Add_FormClosing({
        param($sender, $e)
        if ($script:EkbBusy) { $e.Cancel = $true }
    })

    $setInstallState = {
        param([string]$State, [string]$Value, [string]$Detail)
        $rowInstall.ValueLabel.Text      = $Value
        $rowInstall.ValueLabel.ForeColor = $(switch ($State) { 'ok' { $C.Ok } 'err' { $C.Err } 'warn' { $C.Warn } default { $C.Text } })
        $rowInstall.IconLabel.Text       = [string]$(switch ($State) { 'ok' { $G.Check } 'err' { $G.Cross } 'warn' { $G.Warning } default { $G.Info } })
        $rowInstall.IconLabel.ForeColor  = $rowInstall.ValueLabel.ForeColor
        $txtInstall.Text    = $Detail
        $txtInstall.Visible = [bool]$Detail
        [System.Windows.Forms.Application]::DoEvents()
    }

    $btnBack.Add_Click({ $win.Form.Close() })
    $btnRestart.Add_Click({
        Log 'Restarting to complete the enablement package.'
        $script:EkbResult = 'started'
        Restart-Computer -Force
    })

    $btnPick.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'Windows update package (*.msu)|*.msu'
        $ofd.Title  = "Select the $EkbKb enablement package"
        # Cancelling the picker just returns to this window.
        if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $msu = $ofd.FileName
        Log "Update file selected: $msu"

        $leaf     = [System.IO.Path]::GetFileName($msu)
        $isPrereq = ($leaf -match [regex]::Escape($EkbPrereqKb))
        $isEkb    = ($leaf -match [regex]::Escape($EkbKb))
        if ($isEkb -and -not $script:EkbPrereqOk) {
            if (-not (Confirm-T2F -Title 'Step 1 is not finished' -State 'warn' `
                        -Message "$EkbKb will most likely be refused until $EkbPrereqKb is installed." `
                        -Detail 'Install the required update from step 1 first, restart, and then come back. You can still try now.' `
                        -YesText 'Try anyway' -NoText 'Go back')) {
                Log 'User went back to finish step 1 first.'
                return
            }
        }

        # Compare the file with the fingerprint in its name, so a broken download is caught here
        # in plain words instead of as a signature error from Windows later.
        $script:EkbBusy  = $true
        $btnPick.Enabled = $false
        $btnBack.Enabled = $false
        $progBar.Tag.Value = 0; $progBar.Tag.Phase = 0
        $progBar.Visible = $true; $progText.Visible = $true
        $progText.Text   = 'Checking that the file is complete...'
        $win.Form.Refresh()
        $checkTick = {
            param($pct)
            $progBar.Tag.Value = $pct
            $progBar.Tag.Phase = $progBar.Tag.Phase + 1
            $progBar.Invalidate()
            $progText.Text = 'Checking that the file is complete...  {0:N0}%' -f $pct
            [System.Windows.Forms.Application]::DoEvents()
        }
        $integrity = Test-MsuIntegrity -Path $msu -OnTick $checkTick
        $script:EkbBusy  = $false
        $btnPick.Enabled = $true
        $btnBack.Enabled = $true
        $progBar.Visible = $false; $progText.Visible = $false
        Log ("File check: match={0} size={1} expected={2} actual={3} {4}" -f $integrity.Match, $integrity.Size, $integrity.Expected, $integrity.Actual, $integrity.Note)
        if ($integrity.Match -eq $false) {
            $inCloud = ($msu -match '\\OneDrive')
            $hint = 'Download it again, ideally into a normal folder such as Downloads, and pick the new file. Browsers sometimes stop early or add "(1)" to a second copy.'
            if ($inCloud) { $hint += ' This file is inside OneDrive, which can leave big files unfinished, so copy the new download out of OneDrive first.' }
            $warn = Confirm-T2F -Title 'This file looks damaged' -State 'warn' `
                        -Message 'Its contents do not match the fingerprint Microsoft put in the file name, so it is incomplete or changed.' `
                        -Detail $hint -YesText 'Try anyway' -NoText 'Choose another file'
            if (-not $warn) {
                Log 'User chose another file after the check failed.'
                return
            }
        }

        $viaMicrosoft = 'Microsoft installer window'
        $viaDism      = 'Background (DISM)'
        $method = Show-T2FDialog -Title 'How should it be installed?' `
            -Message 'Either way Windows installs the update itself, and nothing restarts until you choose to.' `
            -Detail ("Microsoft installer window (recommended): Windows opens its own 'Windows Update Standalone Installer' window, exactly as if you double-clicked the file. You confirm there, and Tips2Fix shows the waiting time and progress beside it.$nl$nl" +
                     "Background (DISM): Tips2Fix runs the install itself and shows a percentage bar. No Microsoft window appears.$nl$nl$msu") `
            -Buttons @('Cancel', $viaDism, $viaMicrosoft) -Primary $viaMicrosoft
        if ($method -ne $viaMicrosoft -and $method -ne $viaDism) {
            Log 'User cancelled at the install method choice.'
            return
        }
        Log "Install method: $method"

        $script:EkbBusy  = $true
        $btnPick.Enabled = $false
        $btnBack.Enabled = $false
        $progBar.Tag.Value = -1; $progBar.Tag.Phase = 0
        $progBar.Visible = $true; $progText.Visible = $true
        $progText.Text   = 'Starting...'
        & $setInstallState 'info' 'Working' 'Keep this window open. Your PC is not restarted until you choose to.'
        Write-Host "Installing $EkbKb, please wait..." -ForegroundColor Cyan

        if ($method -eq $viaMicrosoft) {
            # Follows Microsoft's own window and shows the stage and time beside it.
            $script:LastStage = ''
            $onTick = {
                param($phase, $elapsed)
                $progBar.Tag.Value = -1
                $progBar.Tag.Phase = $progBar.Tag.Phase + 1
                $progBar.Invalidate()
                $label = switch ($phase) {
                    'waiting' { 'Waiting for Microsoft''s installer to open...' }
                    'open'    { 'Microsoft''s installer is open. Confirm there to continue.' }
                    default   { 'Windows is applying the update...' }
                }
                $progText.Text = ('{0}      {1:mm\:ss}' -f $label, $elapsed)
                if ($phase -ne $script:LastStage) {
                    $script:LastStage = $phase
                    $detail = switch ($phase) {
                        'waiting' { 'If you do not see Microsoft''s window after a few seconds, look for it in the taskbar.' }
                        'open'    { 'Follow the Microsoft window. This one waits and shows the time.' }
                        default   { 'Microsoft''s window may close by itself when the update is applied.' }
                    }
                    $txtInstall.Text = $detail; $txtInstall.Visible = $true
                }
                Write-Progress -Activity "Installing $EkbKb" -Status ('{0}  {1:mm\:ss}' -f $label, $elapsed)
            }
            $code = Invoke-VisibleInstaller -FilePath "$env:SystemRoot\System32\wusa.exe" -Arguments ('"' + $msu + '" /norestart') `
                        -Label 'wusa (Windows Update Standalone Installer)' -OnTick $onTick
        } else {
            # Called about ten times a second while DISM runs: moves the bar in the window
            # and the matching bar in the PowerShell console.
            $onTick = {
                param($pct, $elapsed)
                $progBar.Tag.Value = $pct
                $progBar.Tag.Phase = $progBar.Tag.Phase + 1
                $progBar.Invalidate()
                $label = if ($pct -ge 0) { 'Installing... {0:N0}%' -f $pct } else { 'Installing...' }
                $progText.Text = ('{0}      {1:mm\:ss} elapsed' -f $label, $elapsed)
                if ($pct -ge 0) { Write-Progress -Activity "Installing $EkbKb" -Status $label -PercentComplete ([int]$pct) }
                else            { Write-Progress -Activity "Installing $EkbKb" -Status $label }
            }
            # DISM's own progress lines (with percentages) feed the bar, so /Quiet is not used.
            $dismArgs = '/Online /Add-Package /PackagePath:"{0}" /NoRestart' -f $msu
            $code = Invoke-LoggedProcess -FilePath "$env:SystemRoot\System32\dism.exe" -Arguments $dismArgs -Label 'DISM /Add-Package' -OnTick $onTick
        }

        Write-Progress -Activity "Installing $EkbKb" -Completed
        $script:EkbBusy  = $false
        $btnPick.Enabled = $true
        $btnBack.Enabled = $true

        $outcome = Get-MsuInstallOutcome -Code $code
        Log "Install result: $($outcome.Kind) ($($outcome.Hex))"

        if ($outcome.Kind -eq 'ok' -or $outcome.Kind -eq 'already') {
            Write-Host $outcome.Text -ForegroundColor Green
            $progBar.Tag.Value = 100; $progBar.Invalidate()
            $progText.Text     = 'Done'
            if ($isPrereq) {
                # Only the first half is done: the user has to restart and come back for the package itself.
                & $setInstallState 'ok' $(if ($outcome.Kind -eq 'already') { 'Already installed' } else { 'Installed' }) `
                    "$($outcome.Text) $EkbPrereqKb is in place. Restart your PC, then run Tips2Fix again and install $EkbKb (steps 2 and 3)."
                $script:EkbResult = 'back'
            } else {
                & $setInstallState 'ok' $(if ($outcome.Kind -eq 'already') { 'Already installed' } else { 'Installed' }) `
                    "$($outcome.Text) Windows 11 $TargetName is ready after a restart. Check winver afterwards."
                $script:EkbResult = 'started'
            }
            $btnPick.Visible    = $false
            $row3.Visible       = $false
            $btnRestart.Visible = $true
            $btnBack.Text       = 'Restart later'
            # The width was measured for the old label, so it has to be re-measured.
            $btnBack.Width = [Math]::Max(118, ([System.Windows.Forms.TextRenderer]::MeasureText($btnBack.Text, $btnBack.Font).Width + 46))
            $btnBack.Invalidate()
            $win.Form.AcceptButton = $btnRestart
            return
        }

        $progBar.Visible = $false; $progText.Visible = $false
        if ($outcome.Kind -eq 'cancelled') {
            & $setInstallState 'warn' 'Cancelled' "$($outcome.Text) You can start again with the orange button."
            return
        }
        if ($outcome.Kind -eq 'damaged') {
            & $setInstallState 'err' "Failed ($($outcome.Hex))" ("$($outcome.Text) Download the file again, ideally into a normal folder such as Downloads " +
                "(not OneDrive), pick the new copy, and try once more. Full details are in the log file.")
            Log "ERROR: the update file was refused as damaged ($($outcome.Hex))."
            return
        }
        $why = if ($outcome.Kind -eq 'notapplicable' -or -not $script:EkbPrereqOk) {
                   "Usually the required update $EkbPrereqKb is missing (step 1), or the file is for another type of PC. Yours needs the $($Inst.Architecture) package."
               } else { "Check that the file is the $EkbKb package for $($Inst.Architecture)." }
        & $setInstallState 'err' "Failed ($($outcome.Hex))" "$($outcome.Text) $why Full details are in the log file."
        Log "ERROR: enablement package installation failed with $($outcome.Hex)."
    })

    $win.Buttons.Controls.Add($btnRestart)
    $win.Buttons.Controls.Add($btnBack)
    $win.Form.AcceptButton = $btnPick

    Show-T2FWindow -Win $win | Out-Null
    return $script:EkbResult
}

# ===================== Bypass patcher and EFI fix =====================

# Runs the standalone patcher next to this script, or does the same work in-process
# when the file is missing. Returns $true on success.
function Invoke-BypassPatcher {
    param([ValidateSet('apply','remove')][string]$Action)

    $cmdPath = Join-Path (Split-Path -Parent $PSCommandPath) $BypassCmdName
    if (Test-Path -LiteralPath $cmdPath) {
        # The path travels in an environment variable so folder names with spaces,
        # apostrophes or ampersands cannot break the command line.
        $env:T2F_CMD = $cmdPath
        $code = Invoke-LoggedProcess -FilePath "$env:SystemRoot\System32\cmd.exe" `
                    -Arguments ('/c call "%T2F_CMD%" /' + $Action) -Label "$BypassCmdName /$Action"
        return ($code -eq 0)
    }

    Log "$BypassCmdName not found next to the script; using the built-in $Action."
    try {
        # Out-Null keeps stray output from turning the return value into an array.
        if ($Action -eq 'apply') { Apply-Bypass | Out-Null } else { Reset-Bypass | Out-Null }
        return $true
    } catch {
        Log "Built-in $Action failed: $($_.Exception.Message)"
        return $false
    }
}

# Runs an installer that shows its own window (such as wusa.exe for a .msu), and keeps
# telling the caller what stage it is in until it is finished. Nothing is hidden: the
# program's own window is what the user sees, and this only watches it.
#   waiting : the program has started but its window has not appeared yet
#   open    : its window is on screen (the user confirms there)
#   working : the Windows servicing worker is busy, so the update is being applied
# Returns the exit code, or -1 if it could not be started.
function Invoke-VisibleInstaller {
    param([string]$FilePath, [string]$Arguments, [string]$Label, [scriptblock]$OnTick, [string]$WorkerName = 'TiWorker')

    Log "Run (its own window): $Label"
    $code = -1
    try {
        $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru
        $null = $p.Handle
        $name = $p.ProcessName
        $ourStart = $p.StartTime   # a hand-off copy cannot start before the process it comes from
        $started = Get-Date
        $sawWindow = $false; $working = $false; $lastWorker = [datetime]::MinValue; $lastPhase = ''; $exitedAt = $null
        while ($true) {
            if ($p.HasExited) {
                # Some installers hand the job to a second copy of themselves. Only a copy
                # that started after ours counts: an older process with the same name is
                # unrelated, and waiting for it would never end. The extra wait is also
                # capped, so this loop can never run forever.
                if (-not $exitedAt) { $exitedAt = Get-Date }
                $handedOff = @(Get-Process -Name $name -ErrorAction SilentlyContinue | Where-Object {
                    $_.Id -ne $p.Id -and (& { try { $_.StartTime -ge $ourStart } catch { $false } })
                })
                if ($handedOff.Count -eq 0 -or ((Get-Date) - $exitedAt).TotalMinutes -ge 30) { break }
            } else {
                $p.Refresh()
                if (-not $sawWindow -and $p.MainWindowHandle -ne [IntPtr]::Zero) { $sawWindow = $true }
            }
            $elapsed = (Get-Date) - $started
            if (((Get-Date) - $lastWorker).TotalMilliseconds -ge 1000) {
                $lastWorker = Get-Date
                $working = [bool](Get-Process -Name $WorkerName -ErrorAction SilentlyContinue)
            }
            # The worker can also be busy with an unrelated update, so it only counts once
            # the installer's window has been seen (or a long time has passed).
            $phase = if ($working -and ($sawWindow -or $elapsed.TotalSeconds -gt 20)) { 'working' }
                     elseif ($sawWindow) { 'open' } else { 'waiting' }
            if ($phase -ne $lastPhase) { Log "  stage: $phase"; $lastPhase = $phase }
            if ($OnTick) { & $OnTick $phase $elapsed }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
        $code = [int]$p.ExitCode
    } catch {
        Log "  could not start: $($_.Exception.Message)"
    }
    Log "  exit code: $code"
    return $code
}

# Microsoft's catalog file names end with the file's SHA-1 fingerprint, for example
# windows11.0-kb5120998-x64_5cdebe...673a.msu. Reading the whole file and comparing
# tells a complete download from a damaged or unfinished one before Windows refuses it.
# Match is $true / $false, or $null when the name carries no fingerprint (renamed file).
# OnTick gets the percent read so far and can keep a window alive.
function Test-MsuIntegrity {
    param([string]$Path, [scriptblock]$OnTick)

    $result = [pscustomobject]@{ Match = $null; Expected = ''; Actual = ''; Size = 0; Note = '' }
    try {
        $item = Get-Item -LiteralPath $Path -ErrorAction Stop
        $result.Size = $item.Length
        if ($item.Length -le 0) { $result.Match = $false; $result.Note = 'The file is empty.'; return $result }

        $m = [regex]::Match($item.Name, '_([0-9a-fA-F]{40})(?:\s*\(\d+\))?\.msu$')
        if (-not $m.Success) { $result.Note = 'The file name has no fingerprint to compare with.'; return $result }
        $result.Expected = $m.Groups[1].Value.ToUpperInvariant()

        $sha    = [System.Security.Cryptography.SHA1]::Create()
        $stream = [System.IO.File]::Open($item.FullName, 'Open', 'Read', 'ReadWrite')
        try {
            $buffer = New-Object byte[] (4MB)
            $done = [long]0; $lastTick = 0
            while (($n = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                [void]$sha.TransformBlock($buffer, 0, $n, $null, 0)
                $done += $n
                $tick = [Environment]::TickCount
                if ($OnTick -and ($tick - $lastTick) -ge 100) {
                    $lastTick = $tick
                    & $OnTick ([double]($done * 100.0 / $item.Length))
                }
            }
            [void]$sha.TransformFinalBlock($buffer, 0, 0)
            $result.Actual = ([BitConverter]::ToString($sha.Hash) -replace '-', '')
        } finally { $stream.Dispose(); $sha.Dispose() }
        $result.Match = ($result.Actual -eq $result.Expected)
    } catch {
        $result.Note = "The file could not be read: $($_.Exception.Message)"
    }
    return $result
}

# Puts a .msu / DISM result into plain words. Kind is ok, already, cancelled,
# notapplicable, damaged or failed.
function Get-MsuInstallOutcome {
    param([int]$Code)

    $hex = '0x{0:X8}' -f $Code
    switch ($Code) {
        0            { return [pscustomobject]@{ Kind = 'ok';            Hex = $hex; Text = 'The update was installed.' } }
        3010         { return [pscustomobject]@{ Kind = 'ok';            Hex = $hex; Text = 'The update was installed and needs a restart.' } }
        2359302      { return [pscustomobject]@{ Kind = 'already';       Hex = $hex; Text = 'This update is already installed on this PC.' } }
        -2147023673  { return [pscustomobject]@{ Kind = 'cancelled';     Hex = $hex; Text = 'You closed or declined Microsoft''s installer, so nothing was installed.' } }
        -2145124329  { return [pscustomobject]@{ Kind = 'notapplicable'; Hex = $hex; Text = 'Windows says this update does not apply to this PC.' } }
        -2146498530  { return [pscustomobject]@{ Kind = 'notapplicable'; Hex = $hex; Text = 'Windows says this update does not apply to this PC.' } }
        577          { return [pscustomobject]@{ Kind = 'damaged';       Hex = $hex; Text = 'Windows could not verify the digital signature of this file. It is usually damaged or an unfinished download.' } }
        -2147024319  { return [pscustomobject]@{ Kind = 'damaged';       Hex = $hex; Text = 'Windows could not verify the digital signature of this file. It is usually damaged or an unfinished download.' } }
        default      { return [pscustomobject]@{ Kind = 'failed';        Hex = $hex; Text = "The installer stopped with code $hex." } }
    }
}

# True on UEFI, False on Legacy BIOS, $null if it cannot be told. Uses the documented
# GetFirmwareType call. The PEFirmwareType registry value exists only inside Windows
# PE, not on a running Windows, so it is kept as a last resort only.
function Test-UefiFirmware {
    try {
        if (-not ('Tips2Fix.FirmwareInfo' -as [type])) {
            Add-Type -Namespace 'Tips2Fix' -Name 'FirmwareInfo' -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetFirmwareType(ref uint FirmwareType);
'@
        }
        [uint32]$ft = 0
        if ([Tips2Fix.FirmwareInfo]::GetFirmwareType([ref]$ft)) {
            if ($ft -eq 2) { return $true }
            if ($ft -eq 1) { return $false }
        }
    } catch {}
    try {
        $t = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name PEFirmwareType -ErrorAction Stop).PEFirmwareType
        if ($t -eq 2) { return $true }
        if ($t -eq 1) { return $false }
    } catch {}
    return $null
}

function Get-FreeDriveLetter {
    param([string]$Preferred = 'Y')
    $used = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object { $_.Name.Substring(0, 1).ToUpper() })
    if ($used -notcontains $Preferred.ToUpper()) { return $Preferred.ToUpper() }
    foreach ($l in 'Z','X','W','V','U','T','S','R') { if ($used -notcontains $l) { return $l } }
    return $null
}

# Guards the delete: only the boot fonts folder of an EFI partition may be cleared.
function Test-EfiFontsFolder {
    param([string]$Path)
    if (-not $Path) { return $false }
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd([char]92)
    $tail = '\' + $EfiFontsRel
    if (-not $full.EndsWith($tail, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    return (Test-Path -LiteralPath $full -PathType Container)
}

function Clear-EfiFonts {
    param([string]$Path)
    if (-not (Test-EfiFontsFolder -Path $Path)) { throw "Refusing to clear an unexpected folder: $Path" }
    # Only files directly inside the folder. Windows rebuilds what it needs.
    $files   = @(Get-ChildItem -LiteralPath $Path -File -Force -ErrorAction SilentlyContinue)
    $bytes   = ($files | Measure-Object -Property Length -Sum).Sum
    $deleted = 0
    foreach ($f in $files) {
        try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $deleted++ }
        catch { Log "Could not delete $($f.FullName): $($_.Exception.Message)" }
    }
    return [pscustomobject]@{ Found = $files.Count; Deleted = $deleted; Bytes = [long]$bytes }
}

function Invoke-EfiFix {
    $nl = [Environment]::NewLine
    Log 'EFI partition fix screen opened.'

    $win = New-T2FWindow -Title 'Fix the system reserved partition error' `
                         -Subtitle 'For: "We couldn''t update the system reserved partition".'

    $win.Body.Controls.Add((New-T2FText -Text ('Setup shows this error when the small EFI System Partition is full. It is almost always old boot font ' +
        'files taking the space Windows needs for the upgrade. Clearing that one folder fixes it, and Windows recreates what it needs.') -Size 10 -Color $C.Text))

    $c1 = New-T2FCard
    $c1.Controls.Add((New-T2FText -Text 'What this does' -Size 10.5 -Color $C.Text -Weight 'Semibold' -MaxWidth $UI.Inner))
    $c1.Controls.Add((New-T2FText -Text ("1. Mounts the EFI partition on a spare drive letter.$nl" +
        "2. Deletes the files inside $EfiFontsRel and nothing else.$nl" +
        '3. Unmounts the partition again.') -Size 9.5 -MaxWidth $UI.Inner))
    $c1.Controls.Add((New-T2FText -Text 'Only works on PCs that boot in UEFI mode. Close Windows Setup first, then run it again afterwards.' -Size 9.5 -MaxWidth $UI.Inner))
    $win.Body.Controls.Add($c1)

    $c2 = New-T2FCard
    $c2.Controls.Add((New-T2FText -Text 'Prefer to do it by hand?' -Size 10.5 -Color $C.Text -Weight 'Semibold' -MaxWidth $UI.Inner))
    $c2.Controls.Add((New-T2FText -Text ('In a Command Prompt opened as administrator: mountvol Y: /s, then Y:, then cd EFI\Microsoft\Boot\Fonts, ' +
        'then del *.* and answer Y. Finish with mountvol Y: /d. "Copy commands" puts them on your clipboard.') -Size 9.5 -MaxWidth $UI.Inner))
    $win.Body.Controls.Add($c2)

    $rowResult = New-T2FStatusRow -Label 'Result' -State 'info' -Value 'Not run yet' -Width $UI.Card
    $win.Body.Controls.Add($rowResult)
    $txtResult = New-T2FText -Text '' -Size 9.5 -Color $C.Text -MaxWidth $UI.Card
    $txtResult.Visible = $false
    $win.Body.Controls.Add($txtResult)

    $setResult = {
        param([string]$State, [string]$Value, [string]$Detail)
        $col = switch ($State) { 'ok' { $C.Ok } 'err' { $C.Err } 'warn' { $C.Warn } default { $C.Text } }
        $rowResult.ValueLabel.Text      = $Value
        $rowResult.ValueLabel.ForeColor = $col
        $rowResult.IconLabel.Text       = [string]$(switch ($State) { 'ok' { $G.Check } 'err' { $G.Cross } 'warn' { $G.Warning } default { $G.Info } })
        $rowResult.IconLabel.ForeColor  = $col
        $txtResult.Text    = $Detail
        $txtResult.Visible = [bool]$Detail
        [System.Windows.Forms.Application]::DoEvents()
    }

    $btnBack = New-T2FButton -Text 'Back' -Kind 'quiet'
    $btnCopy = New-T2FButton -Text 'Copy commands'
    $btnRun  = New-T2FButton -Text 'Run the fix' -Kind 'primary'

    $btnBack.Add_Click({ $win.Form.Close() })

    $btnCopy.Add_Click({
        $text = "mountvol $EfiMountLetter`: /s$nl" + "$EfiMountLetter`:$nl" + "cd $EfiFontsRel$nl" + "del *.*$nl" + "mountvol $EfiMountLetter`: /d"
        try {
            [System.Windows.Forms.Clipboard]::SetText($text)
            Log 'Copied EFI fix commands to clipboard.'
            $this.Text = 'Copied'
        } catch { $this.Text = 'Copy failed' }
        $this.Invalidate()
    })

    $btnRun.Add_Click({
        if ((Test-UefiFirmware) -eq $false) {
            & $setResult 'warn' 'Not applicable' 'This PC starts in Legacy BIOS mode, so it has no EFI partition and this error does not come from there.'
            Log 'EFI fix skipped: Legacy BIOS firmware.'
            return
        }
        if (-not (Confirm-T2F -Title 'Clear the EFI boot fonts?' -State 'warn' `
                    -Message 'Tips2Fix will mount the EFI System Partition and delete the files in its boot fonts folder.' `
                    -Detail ("Folder: $EfiFontsRel$nl$nl" + 'Close Windows Setup first. Windows recreates the fonts it needs, so this is safe.') `
                    -YesText 'Clear the fonts' -NoText 'Cancel')) {
            Log 'User declined the EFI fix.'
            return
        }

        $letter = Get-FreeDriveLetter -Preferred $EfiMountLetter
        if (-not $letter) {
            & $setResult 'err' 'Failed' 'No spare drive letter is available to mount the EFI partition. Free one up and try again.'
            return
        }

        $btnRun.Enabled = $false
        & $setResult 'info' 'Working...' "Mounting the EFI partition on ${letter}:"
        $mounted = $false
        try {
            $mc = Invoke-LoggedProcess -FilePath "$env:SystemRoot\System32\mountvol.exe" -Arguments "${letter}: /s" -Label "mountvol ${letter}: /s"
            if ($mc -ne 0) { throw "mountvol could not mount the EFI partition (exit code $mc)." }
            $mounted = $true

            $fonts = "${letter}:\$EfiFontsRel"
            if (-not (Test-Path -LiteralPath $fonts -PathType Container)) {
                & $setResult 'ok' 'Nothing to clear' "The folder $EfiFontsRel does not exist on this partition, so the fonts are not what is filling it."
                Log 'EFI fix: fonts folder not present.'
            } else {
                $r = Clear-EfiFonts -Path $fonts
                Log "EFI fix: found $($r.Found), deleted $($r.Deleted), freed $($r.Bytes) bytes."
                if ($r.Deleted -eq $r.Found) {
                    & $setResult 'ok' 'Cleared' ("Removed $($r.Deleted) file(s) and freed $(Format-Size $r.Bytes). Run Windows Setup again.")
                } else {
                    & $setResult 'warn' 'Partly cleared' ("Removed $($r.Deleted) of $($r.Found) files. Run as administrator and try again. Details are in the log.")
                }
            }
        } catch {
            Log "EFI fix failed: $($_.Exception.Message)"
            & $setResult 'err' 'Failed' "$($_.Exception.Message) Make sure Tips2Fix is running as administrator."
        } finally {
            if ($mounted) {
                Invoke-LoggedProcess -FilePath "$env:SystemRoot\System32\mountvol.exe" -Arguments "${letter}: /d" -Label "mountvol ${letter}: /d" | Out-Null
            }
            $btnRun.Enabled = $true
        }
    })

    $win.Buttons.Controls.Add($btnRun)
    $win.Buttons.Controls.Add($btnCopy)
    $win.Buttons.Controls.Add($btnBack)
    $win.Form.AcceptButton = $btnRun

    Show-T2FWindow -Win $win | Out-Null
}

function Invoke-IsoFlow {
    param($Os, $Inst)

    # Every step that fails or is cancelled returns to the ISO screen instead of
    # ending the tool, so Back always leads somewhere.
    while ($true) {
        $req = Show-IsoRequirements -Inst $Inst
        if ($req.Action -ne 'selected') { return 'back' }

        $isoPath = $req.Path
        $isoName = [System.IO.Path]::GetFileNameWithoutExtension($isoPath)
        Log "ISO selected: $isoPath"

        if (-not (Confirm-T2F -Title 'Mount this ISO?' `
                    -Message 'Tips2Fix will mount the ISO as a temporary drive so Windows Setup can read it. It is unmounted again when the tool closes.' `
                    -Detail $isoPath -YesText 'Mount' -NoText 'Cancel')) {
            Log 'User declined to mount the ISO.'
            continue
        }

        Log 'Mounting ISO...'
        Write-Host 'Mounting the ISO...' -ForegroundColor Cyan
        $drive = $null; $isoBytes = 0
        try {
            $disk = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
            $script:MountedIsoPath = $isoPath
            for ($i = 0; $i -lt 60; $i++) {
                $vol = Get-Volume -DiskImage $disk -ErrorAction SilentlyContinue | Where-Object DriveLetter
                if ($vol -and $vol.DriveLetter) {
                    $drive = [string]$vol.DriveLetter + ':'
                    $isoBytes = [long]$vol.Size
                    if (Test-Path ($drive + [char]92)) { break }
                }
                Start-Sleep -Seconds 1
            }
        } catch {
            Log "Mount failed: $($_.Exception.Message)"
        }

        if (-not $drive) {
            Dismount-IsoSafely
            Inform-T2F -Title 'The ISO could not be mounted' -State 'err' `
                       -Message 'Windows did not give the ISO a drive letter.' `
                       -Detail 'Check that the file opens when you double-click it in File Explorer. Other virtual drive programs can also get in the way.'
            continue
        }

        $isoRoot = $drive + [char]92
        Log "Mounted at $drive (about $(Format-Size $isoBytes))"

        $setupOnIso = Resolve-SetupPath -Root $isoRoot
        if (-not $setupOnIso) {
            Dismount-IsoSafely
            Inform-T2F -Title 'This is not a Windows installation ISO' -State 'err' `
                       -Message 'The file does not contain Windows Setup.' `
                       -Detail 'A Windows 11 ISO has sources\setupprep.exe or setup.exe inside it. Download the ISO again from Microsoft.'
            continue
        }

        $iso = Get-IsoBuildInfo -Root $isoRoot
        if ($iso.Build -gt 0) {
            Log "ISO build: $($iso.Build)  ($($iso.BuildLab))"
            Write-Host ('ISO build detected: {0}' -f $iso.Build) -ForegroundColor DarkCyan
            if ($iso.Build -lt $TargetBuild) {
                if (-not (Confirm-T2F -Title 'This ISO is an older build' -State 'warn' `
                            -Message "The ISO is build $($iso.Build), older than Windows 11 $TargetName (build $TargetBuild)." `
                            -YesText 'Use it anyway' -NoText 'Choose another ISO')) {
                    Dismount-IsoSafely
                    continue
                }
            }
        }

        if ((Show-UpgradePreflight -IsoRoot $isoRoot -Inst $Inst) -ne 'next') {
            Dismount-IsoSafely
            continue
        }

        # --- How to run Setup
        $script:ChoiceGroup = @()
        $win = New-T2FWindow -Title 'How should Setup run?' -Subtitle 'Both options install exactly the same Windows.'
        $cDirect = New-T2FChoice -Title 'Run straight from the mounted ISO' `
            -Description 'Nothing is copied. Saves disk space and about 10-20 minutes.' -IsChecked $true -Badge 'FASTEST'
        $win.Body.Controls.Add($cDirect)
        $cExtract = New-T2FChoice -Title 'Extract the ISO to a folder first' `
            -Description ('Copies about ' + (Format-Size $isoBytes) + ' to your Desktop. Useful if you want to keep the files afterwards.')
        $win.Body.Controls.Add($cExtract)

        $script:SourceNav = 'back'
        $bBack = New-T2FButton -Text 'Back' -Kind 'quiet'
        $bNext = New-T2FButton -Text 'Continue' -Kind 'primary'
        $bBack.Add_Click({ $script:SourceNav = 'back'; $win.Form.Close() })
        $bNext.Add_Click({ $script:SourceNav = 'next'; $win.Form.Close() })
        $win.Buttons.Controls.Add($bNext)
        $win.Buttons.Controls.Add($bBack)
        $win.Form.AcceptButton = $bNext
        Show-T2FWindow -Win $win | Out-Null
        if ($script:SourceNav -ne 'next') { Dismount-IsoSafely; continue }

        $runDirect = $cDirect.Tag.Checked
        return (Complete-IsoSetup -IsoRoot $isoRoot -IsoName $isoName -IsoBytes $isoBytes `
                                  -SetupOnIso $setupOnIso -RunDirect $runDirect)
    }
}

function Complete-IsoSetup {
    param([string]$IsoRoot, [string]$IsoName, [long]$IsoBytes, [string]$SetupOnIso, [bool]$RunDirect)

    $isoRoot = $IsoRoot; $isoName = $IsoName; $isoBytes = $IsoBytes
    $setupOnIso = $SetupOnIso
    $runDirect = $RunDirect
    Log ('Setup source: ' + $(if ($runDirect) { 'mounted ISO' } else { 'extracted folder' }))

    $setupPath = $setupOnIso

    if (-not $runDirect) {
        $dest = Join-Path $desktop $isoName
        if (-not (Confirm-T2F -Title 'Extract here?' `
                    -Message 'Windows 11 files will be extracted to this folder.' -Detail $dest `
                    -YesText 'Extract here' -NoText 'Choose another folder')) {
            $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
            $fbd.Description = "Select a folder in which to create: $isoName"
            if ($fbd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
                Log 'User cancelled the extraction folder picker; running Setup from the mounted ISO instead.'
                $runDirect = $true
            } else {
                $dest = Join-Path $fbd.SelectedPath $isoName
            }
        }

        if (-not $runDirect) {
            $free   = Get-FreeSpaceBytes -Path $dest
            $needed = [long]($isoBytes * 1.05)
            if ($free -ge 0 -and $free -lt $needed) {
                $drv = Split-Path -Path $dest -Qualifier
                if (-not (Confirm-T2F -Title 'Not enough free space' -State 'warn' `
                            -Message ('Extracting needs about ' + (Format-Size $needed) + ' on ' + $drv + ', but only ' + (Format-Size $free) + ' is free.') `
                            -Detail 'Running Setup straight from the mounted ISO needs no extra space and installs exactly the same Windows.' `
                            -YesText 'Run from the ISO' -NoText 'Go back')) {
                    return 'back'
                }
                Log "Not enough space to extract to $dest; running Setup from the mounted ISO instead."
                $runDirect = $true
            }
        }
    }

    if (-not $runDirect) {
        if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }
        Log "Extracting to $dest"
        Copy-IsoContent -Source $isoRoot -Destination $dest -TotalBytes $isoBytes
        Dismount-IsoSafely

        $setupPath = Resolve-SetupPath -Root $dest
        if (-not $setupPath) {
            Inform-T2F -Title 'Setup files are missing' -State 'err' `
                       -Message 'The extracted folder does not contain Windows Setup.' -Detail $dest
            return 'back'
        }

        Write-Host ''
        Write-Host 'When the installation is completely finished, you can safely delete:' -ForegroundColor Yellow
        Write-Host "  $dest"
    }

    Write-Host ('Setup executable: {0}' -f $setupPath) -ForegroundColor DarkCyan

    # Written only now, right before Setup reads them, so nothing is left behind if the
    # user stops earlier to download an ISO or cancels along the way.
    $nl = [Environment]::NewLine
    if (Confirm-T2F -Title 'Apply the bypass values?' `
            -Message 'These tell Windows Setup to skip the TPM, Secure Boot, RAM, storage and CPU-model checks.' `
            -Detail ('LabConfig, MoSetup, HwReqChk and PCHC values are written. The HwReqChk values are what keep ' +
                     '"Keep personal files and apps" available during the upgrade.' + $nl + $nl +
                     'You can undo all of it later with "Undo the bypass".') `
            -YesText 'Apply' -NoText 'Skip') {
        if (-not (Invoke-BypassPatcher -Action 'apply')) {
            Inform-T2F -Title 'The bypass could not be applied' -State 'warn' `
                -Message 'Setup may refuse to run on this hardware.' -Detail "Details are in the log: $logPath"
        }
    } else {
        Log 'User declined the bypass keys; Setup may refuse to run on unsupported hardware.'
    }

    if (-not (Confirm-T2F -Title 'Start Windows 11 Setup?' `
                -Message 'Windows Setup will open. From there you choose what to keep, and Setup takes over from this tool.' `
                -Detail 'When Setup asks, choose "Keep personal files and apps".' `
                -YesText 'Start Setup' -NoText 'Not yet')) {
        Write-Host 'Setup launch cancelled by the user.' -ForegroundColor Yellow
        Log 'User cancelled setup launch.'
        return 'stopped'
    }

    Invoke-SetupFlow -SetupPath $setupPath
    return 'started'
}

# ===================== Bootstrap =====================

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo 'PowerShell'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    $psi.Verb = 'runas'
    try { [System.Diagnostics.Process]::Start($psi) | Out-Null } catch { exit }
    exit
}

$scriptDir = Split-Path -Parent $PSCommandPath
$logPath = Initialize-T2FLog -PrimaryDir (Join-Path $scriptDir 'Logs') `
                             -FallbackDir (Join-Path $env:LOCALAPPDATA 'Tips2Fix\Logs') -Keep $LogKeep
Log "Script started. Target: Windows 11 $TargetName (build $TargetBuild)."

Write-Host ''
Write-Host "  Tips2Fix - Windows 11 $TargetName Installer  v$AppVersion" -ForegroundColor Yellow
Write-Host '  Every step asks for your permission. Nothing runs silently.' -ForegroundColor Gray
Write-Host ("  Log: " + $(if ($logPath) { $logPath } else { '(no writable place for a log file was found)' })) -ForegroundColor DarkGray
Write-Host ''

$installStarted = $false

try {
    Write-Host 'Checking CPU support for SSE4.2...' -ForegroundColor Cyan
    $cpuName = '(unknown CPU)'
    try { $cpuName = ((Get-CimInstance Win32_Processor -ErrorAction Stop) | Select-Object -First 1).Name.Trim() } catch {}
    $sse  = Get-Sse42Support
    $os   = Get-OsInfo
    $inst = Get-InstalledEditionInfo
    Log "CPU: $cpuName | SSE4.2: $($sse.Supported) via $($sse.Method)"
    $hw = $null   # read after the first screen, so the tool opens instantly
    Log "OS: $($os.Friendly) build $($os.Build).$($os.UBR) | $($inst.Edition) | $($inst.LanguageTag) | $($inst.Architecture)"

    if ($os.AlreadyOn) {
        Inform-T2F -Title 'Already up to date' -State 'ok' -Message "This PC is already running $($os.Friendly). There is nothing to upgrade."
        Log 'Already on the target build or newer. Exiting.'
        exit
    }

    # Screens are driven from here so that Back always lands on the previous one
    # rather than ending the tool.
    $step = 'welcome'
    while ($step -ne 'done') {
        switch ($step) {

            'welcome' {
                if ((Show-Welcome) -eq 'next') { Log 'Disclaimer accepted.'; $step = 'scan' } else { $step = 'done' }
            }

            'scan' {
                if (-not $hw) {
                    $hw = Get-HardwareReport
                    $hf = $hw.Facts
                    Log ("Hardware: {0} cores / {1} threads | RAM {2} GB | disk {3} GB ({4} GB free) | {5} | Secure Boot {6} | TPM present {7} spec {8}" -f
                         $hf.Cores, $hf.Threads, $hf.RamGB, $hf.DiskGB, $hf.DiskFreeGB, $hf.Firmware, $hf.SecureBoot, $hf.TpmPresent, $hf.TpmSpec)
                }
                $nav = Show-SystemScan -Os $os -Inst $inst -Sse $sse -Hw $hw
                if ($nav -eq 'back') { $step = 'welcome' }
                elseif ($nav -ne 'next') { $step = 'done' }
                elseif ($sse.Supported -eq $false -and -not (Confirm-T2F `
                            -Title 'This processor cannot run Windows 11 26H2' -State 'err' `
                            -Message "Without SSE4.2, Windows 11 $TargetName will not boot even if Setup completes successfully." `
                            -Detail 'Continuing is very likely to leave this PC unable to start. Windows 11 23H2 is the newest version it can run.' `
                            -YesText 'Continue anyway' -NoText 'Go back')) {
                    Log 'User stopped at the SSE4.2 warning.'
                }
                else {
                    if ($sse.Supported -eq $false) { Log 'WARNING: user chose to continue without SSE4.2 support.' }
                    $step = 'mode'
                }
            }

            'mode' {
                $mode = Show-ModeSelection -Os $os
                Log "Mode selected: $mode"
                switch ($mode) {
                    'back' { $step = 'scan' }
                    'apply' {
                        if (Confirm-T2F -Title 'Apply the bypass values?' `
                                -Message 'These tell Windows Setup to skip the TPM, Secure Boot, RAM, storage and CPU-model checks.' `
                                -Detail ('LabConfig, MoSetup, HwReqChk and PCHC values are written, and nothing else happens. ' +
                                         'You can run Windows Setup yourself afterwards, and remove the values later with "Undo the bypass".') `
                                -YesText 'Apply' -NoText 'Cancel') {
                            if (Invoke-BypassPatcher -Action 'apply') {
                                Inform-T2F -Title 'Bypass applied' -State 'ok' `
                                    -Message 'The bypass values are set. Windows Setup will now skip the hardware checks.'
                            } else {
                                Inform-T2F -Title 'The bypass could not be applied' -State 'err' `
                                    -Message 'Something went wrong while writing the values.' -Detail "Details are in the log: $logPath"
                            }
                        }
                    }
                    'reset' {
                        if (Confirm-T2F -Title 'Remove the bypass values?' -State 'warn' `
                                -Message 'Every registry value the bypass added will be deleted and the Windows defaults restored.' `
                                -Detail 'LabConfig, MoSetup, HwReqChk and PCHC values. Keys that hold other settings are left alone.' `
                                -YesText 'Remove them' -NoText 'Cancel') {
                            if (Invoke-BypassPatcher -Action 'remove') {
                                Inform-T2F -Title 'Registry restored' -State 'ok' -Message 'All bypass values have been removed.'
                            } else {
                                Inform-T2F -Title 'The values could not be removed' -State 'err' `
                                    -Message 'Something went wrong while removing the values.' -Detail "Details are in the log: $logPath"
                            }
                        }
                    }
                    'efi' { Invoke-EfiFix }
                    'ekb' {
                        $r = Invoke-EkbFlow -Os $os -Inst $inst
                        if ($r -ne 'back') { $installStarted = ($r -eq 'started'); $step = 'done' }
                    }
                    'iso' {
                        $r = Invoke-IsoFlow -Os $os -Inst $inst
                        if ($r -ne 'back') { $installStarted = ($r -eq 'started'); $step = 'done' }
                    }
                    default { $step = 'done' }
                }
            }
        }
    }

    if ($installStarted) {
        if (Confirm-T2F -Title 'Enjoy Windows 11!' -State 'ok' `
                -Message 'Would you like to open the Tips2Fix YouTube channel and subscribe?' `
                -YesText 'Open YouTube' -NoText 'No thanks' -CopyText $SubscribeUrl) {
            try { Start-Process $SubscribeUrl; Log 'Opened YouTube subscribe link.' }
            catch { Log "Could not open YouTube link: $_" }
        }
    }

    Log "Finished. Duration: $((Get-Date) - $scriptStart)"
}
catch {
    Log "ERROR: $_"
    try {
        Inform-T2F -Title 'Something went wrong' -State 'err' -Message "$_" -Detail "Full details are in the log: $logPath"
    } catch {}
}
finally {
    Dismount-IsoSafely
    Read-Host 'Script finished. Press Enter to close this window...'
}
