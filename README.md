# Tips2Fix Windows 11 26H2 Installer

**Safe Confirmed Edition**

A guided tool for upgrading older PCs to Windows 11 26H2, including PCs that Microsoft lists as unsupported. It shows you what it found, explains each step, and asks before it changes anything. Everything it does is written to a log file in a `Logs` folder next to the tool.

Made and maintained by Tips2Fix.

## What's new in v1.2.0

- **Keeps your files and apps.** The tool now sets the `HwReqChk` compatibility values. They are what keep "Keep personal files and apps" available during an upgrade. Earlier versions relied on `/product server`, which grays that option out, so Setup could only do a clean install.
- **Tells you exactly which ISO to download.** It reads your installed edition, language and architecture and lists them as a checklist to match on Microsoft's download page. It can open that page for you, but only after asking, and it never downloads anything by itself.
- **The installer stays open while you download.** Opening a download page puts the browser beside the tool instead of closing it, so you carry on with **Select ISO from PC** when the download finishes rather than starting over.
- **Direct download buttons for the enablement package.** One click each for the x64 and ARM64 `.msu`, with the one your PC needs marked. The tool also checks whether the required `KB5120998` update is already installed and tells you before you get an error from DISM.
- **Back buttons that go back.** Every screen has one, and it returns to the previous screen instead of quitting.
- **Larger text** throughout, so the screens are easier to read.
- **Live progress while installing.** When you install the enablement package, an animated bar with a percentage and a running timer shows in the window, and the same progress bar appears in the PowerShell console. Extracting an ISO shows the same two bars. The window cannot be closed by accident while an install is running.
- **Clearer steps.** The fast-update screen now has numbered markers (a tick once a step is done), and step 3 is the strongest card on the screen with its own button, so it is obvious what to click next.
- **Windows behave like normal windows.** They are no longer forced on top of everything, so you can click the PowerShell console or any other program while the tool is open. Each window still comes to the front once when it opens, and dialogs stay in front of the window that opened them.
- **Disabled buttons look disabled.**
- **A full hardware picture on the "Your system" screen.** It shows your processor model, cores and speed, memory, storage, UEFI or Legacy BIOS, Secure Boot and TPM, each with its status against Microsoft's Windows 11 minimum. Anything below the minimum is marked, with a note that the tool tells Setup to skip that check, and a plain conclusion sits under the table. Whatever cannot be read is shown as "Could not be read" and never guessed. It also says that Microsoft's own list of supported processors is not checked here, and points to PC Health Check for that.
- **Microsoft's own installer window for the update.** In the fast-update step you choose how to install: Microsoft's own "Windows Update Standalone Installer" window (nothing hidden, you confirm there), or the background method with a percentage bar. Beside Microsoft's window the tool shows the stage and a running timer: waiting for the window to open, window open, then Windows applying the update.
- **Copy link next to every "Open browser".** Each prompt shows the exact address and lets you copy it instead of opening it.
- **Three stand-alone tools**: apply the bypass only, undo it, and fix "We couldn't update the system reserved partition". They sit under "Or just use one tool" on the options screen.
- **`Bypass-Requirements.cmd`**, a standalone patcher you can use without the installer.
- **An About page on every screen** ("About this tool", bottom left). It explains in plain words what the tool reads, what it can change, what it never does, and where it stands with Microsoft.
- **A cleaner header** with a fixed layout, so titles and subtitles can no longer overlap and a keyboard focus ring for Tab users.
- **Checks your ISO before Setup starts.** The ISO's language and edition are compared with your installed Windows, along with free disk space. A mismatch is the most common reason "Keep personal files and apps" disappears, so you find out before you begin instead of on the last Setup screen.
- **Fast update for 24H2 and 25H2.** Windows 11 26H2 is delivered as a small enablement package (`KB5121794`, about 174 KB). If your PC already runs 24H2 or 25H2, you don't need the 7.9 GB ISO at all.
- **Reliable SSE4.2 detection.** The CPU check now asks Windows directly through the `IsProcessorFeaturePresent` API instead of guessing from the processor name.
- **`/product server` is now a last resort.** It became unreliable in 2026. You can still retry Setup with it, but only after a warning that explains what it costs.
- **Run Setup straight from the mounted ISO.** Extracting the ISO is optional now, which saves about 7.9 GB and 10 to 20 minutes.
- **Faster extraction when you do extract.** It uses `robocopy`, and the progress bar follows the bytes copied instead of the file count, so it no longer sits at 99%.
- **Nothing changes until you're ready.** The registry values are written right before Setup starts, so nothing is left behind if you stop to download an ISO first.
- **Safer cleanup.** The ISO is always unmounted, even if something fails. Undo no longer deletes a `LabConfig` key that already held other settings.
- **The launcher works from any folder.** Earlier versions failed to start from a folder with an apostrophe in its path, such as `C:\Users\O'Brien`.
- **New look.** A rebuilt interface with clearer screens and fewer pop-ups. It only uses the Segoe UI fonts that come with both Windows 10 and Windows 11, so it looks the same on both.

## Before you start: SSE4.2

Since Windows 11 24H2, Windows needs a processor with the SSE4.2 instruction set (which includes POPCNT) to start. The same applies to 25H2 and 26H2.

**No registry change, Rufus option or installer trick gets around this.** On a CPU without SSE4.2, Windows 11 26H2 will not boot even if Setup finishes. Windows 11 23H2 is the newest version such a PC can run.

TPM 2.0, Secure Boot, the RAM and storage checks, and the list of supported CPUs can all be skipped, and this tool does that for you.

SSE4.2 is only missing on processors from around 2007 and earlier. The tool checks it before anything else.

## Coming from Windows 10?

Windows 10 support ended on 14 October 2025, so most people using this tool are on Windows 10 22H2. You can go straight from Windows 10 to 26H2. There is no need to install 24H2 or 25H2 first.

Use **Install from a Windows 11 ISO**. The fast update only works on PCs that already run Windows 11 24H2 or 25H2.

### What decides whether you keep your files and apps

Windows Setup only offers "Keep personal files and apps" when all three of these line up. The tool checks them for you before Setup starts.

| Must match | Why |
|---|---|
| **Language** | An English ISO on a German Windows will not keep anything. Download the ISO in the same language as your Windows. |
| **Edition** | Home to Home, Pro to Pro. An Enterprise ISO on a Pro PC forces a clean install. You can check your edition with `winver`. |
| **Free space** | Setup needs about 25 GB free on your system drive. |

### Two more things

- **Start the upgrade from inside Windows**, the way this tool does. Booting from a USB stick forces a clean install and your programs are gone.
- **Avoid the `/product server` retry if you can.** It skips more checks, but it normally grays out "Keep personal files and apps". That is why the tool shows a warning before using it.

Make a backup first anyway. An in-place upgrade usually goes smoothly, but not always.

## What's in the download

- `Run-Installer.bat` starts the tool as administrator.
- `Windows11_QuickInstaller.ps1` is the installer itself.
- `Bypass-Requirements.cmd` is the standalone patcher. The installer runs it when you apply or undo the bypass, and you can also use it on its own (see below).
- `README.md` is this file.

Keep the files in the same folder. If `Bypass-Requirements.cmd` is missing, the installer does the same job itself.

## Requirements

- Windows 10 or Windows 11
- Administrator rights (you will see a UAC prompt)
- Windows PowerShell 5.1, which is built into Windows 10 and 11
- A processor with SSE4.2 (the tool checks this)
- Either the `KB5121794` enablement package (about 174 KB) or a Windows 11 26H2 ISO (about 7.9 GB), depending on your PC

## Quick start

1. Download the ZIP from the table at the bottom of this page and extract it to a folder on your PC.
2. Right-click `Run-Installer.bat` and choose **Run as administrator**.
3. Read the first screen and click **I understand, continue**.
4. Check the **Your system** screen. It shows your Windows version, edition, language, architecture and the SSE4.2 result.
5. Choose how to upgrade. The best option for your PC is already selected.
6. Follow the steps. The tool asks before every change, and **Back** always returns to the previous screen.

## The options

### Fast update (enablement package)

Selected automatically if your PC runs Windows 11 24H2 or 25H2. The screen walks through three steps and stays open the whole time.

**Step 1: the required update `KB5120998`.** The tool reads your build number and tells you whether it is already installed, because `KB5121794` will not apply without it. If it is missing you get three buttons: a direct download of the x64 package, **Open Update Catalog** to pick a build yourself or to get the ARM64 file, and **Check again** to re-read your build number after you install it, so you never have to close the tool and start over. Running Windows Update once does the same job. Note that this one is a full cumulative update of about 4.3 GB, not a small package, and Windows normally needs a restart before it reports it as installed.

**Step 2: download `KB5121794`.** Buttons open direct links on Microsoft's own delivery server, with the one your PC needs marked:

| For | File | Size |
|---|---|---|
| Intel and AMD | `Windows11.0-KB5121794-x64.msu` | about 173 KB |
| ARM64 | `Windows11.0-KB5121794-arm64.msu` | about 175 KB |

An **Update Catalog** button is there too, in case a direct link stops working. The download itself is handled by your browser.

**Step 3: install the file you downloaded.** Click **Select .msu file and install** and pick a downloaded file. It installs whichever one you pick: use it for `KB5120998` first if step 1 says it is missing, restart, and then for `KB5121794`. If you pick the package while step 1 is unfinished, the tool warns you first. After `KB5120998` it tells you to restart and come back, and does not pretend the upgrade is finished. Before anything is installed, the tool checks the file. Microsoft puts the file's SHA-1 fingerprint at the end of its file name, so the tool reads the file and compares it. If they do not match, the download is unfinished or damaged, and you are told so in plain words instead of getting a signature error from Windows (`0x80070241`) later. Big files inside OneDrive are a common cause, so download into a normal folder such as Downloads. A renamed file simply skips the check. Then choose how to install it:

- **Microsoft installer window (recommended).** Windows opens its own Windows Update Standalone Installer, exactly as if you had double-clicked the file. You confirm there. Tips2Fix stays open beside it and shows the stage (waiting for the window, window open, Windows applying the update) with a running timer. This method cannot show a percentage, because Microsoft's installer does not report one.
- **Background (DISM).** The tool runs `DISM /Online /Add-Package` itself and shows a percentage bar. No Microsoft window appears.

Either way the Tips2Fix window stays open and shows an animated bar and a running timer, with the same progress in the PowerShell console. With DISM the bar fills with the real percentage, and until DISM reports its first one the bar glides back and forth to show it is working. When it finishes, the result appears on the same screen and the footer turns into **Restart now**. If it fails, you see the reason there instead of losing the screen. If you close or decline Microsoft's window, the tool says so and lets you start again.

One restart and you are on 26H2. No hardware check runs, because Windows is already installed and only the version changes.

### Install from a Windows 11 ISO

For Windows 10 and Windows 11 23H2 or older, where a full Setup is needed. The tool:

1. Shows you which ISO to download and can open Microsoft's download page, staying open while you download. When the file is ready, click **Select ISO from PC**.
2. Mounts your ISO, checks that it contains Windows Setup and reads its build number.
3. Compares the ISO's language and edition with your Windows and checks free space.
4. Lets you run Setup straight from the mounted ISO or extract it to a folder first.
5. Asks to set the registry values below, then asks before starting Setup with `/compat ignorewarning /dynamicupdate disable /migratedrivers all`.

The registry values are only written at step 5, right before Setup starts, so nothing changes if you stop earlier. They are (DWORD 1 unless noted):

- `HKLM\SYSTEM\Setup\LabConfig\BypassTPMCheck`
- `HKLM\SYSTEM\Setup\LabConfig\BypassSecureBootCheck`
- `HKLM\SYSTEM\Setup\LabConfig\BypassRAMCheck`
- `HKLM\SYSTEM\Setup\LabConfig\BypassCPUCheck`
- `HKLM\SYSTEM\Setup\LabConfig\BypassStorageCheck`
- `HKLM\SYSTEM\Setup\LabConfig\BypassDiskCheck`
- `HKLM\SYSTEM\Setup\MoSetup\AllowUpgradesWithUnsupportedTPMOrCPU`
- `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\HwReqChk\HwReqChkVars` (REG_MULTI_SZ). This is the one that keeps "Keep personal files and apps" available.
- `HKCU\Software\Microsoft\PCHC\UpgradeEligibility`

It also clears the saved result of any earlier failed attempt (`CompatMarkers`, `Shared` and `TargetVersionUpgradeExperienceIndicators` under `AppCompatFlags`), because Windows otherwise keeps reusing it.

If Setup still refuses to run, the tool's Setup window has a **Setup was blocked - retry** button. It starts Setup again with `/product server`, after a warning.

How the values work together: `MoSetup\AllowUpgradesWithUnsupportedTPMOrCPU` covers the in-place upgrade (it still expects at least TPM 1.2). The `LabConfig` values cover the Setup stage. `HwReqChkVars` makes the compatibility check report a pass, which is what keeps your files and apps. The tool sets all of them.

The last three options sit under **Or just use one tool** on the same screen.

### Apply the requirement bypass only

For people who want to run Windows Setup themselves. It writes the registry values listed above, asks first, and then stops. Nothing is mounted, downloaded or started.

### Undo the bypass

- Removes every registry value listed above.
- Deletes the `LabConfig` and `HwReqChk` keys only if they are empty afterwards, so settings that were there before are kept.

Every registry change is shown to you first and written to the log.

### Fix "We couldn't update the system reserved partition"

Setup shows this error right after you click Next when the small EFI System Partition is full, almost always because of old boot font files. This option:

1. Checks that the PC starts in UEFI mode (Legacy BIOS PCs do not have this problem).
2. Mounts the EFI partition on a spare drive letter, `Y:` if it is free.
3. Deletes the files inside `EFI\Microsoft\Boot\Fonts`, and only that folder. It refuses to touch any other path, and it leaves subfolders and every other boot file alone. Windows recreates the fonts it needs.
4. Unmounts the partition again and shows how much space was freed.

Close Windows Setup first, run the fix, then start Setup again. If you prefer the manual way, **Copy commands** puts the same commands on your clipboard: `mountvol Y: /s`, `Y:`, `cd EFI\Microsoft\Boot\Fonts`, `del *.*`, `mountvol Y: /d`, run in a Command Prompt opened as administrator.

## Using the patcher on its own

`Bypass-Requirements.cmd` needs no PowerShell and no ISO. Double-click it for a small menu: apply, remove, or show what is currently set. It asks for administrator rights itself.

It also accepts options, which is how the installer calls it:

| Option | What it does |
|---|---|
| `/apply` | Sets the bypass values without asking |
| `/remove` | Removes them without asking |
| `/status` | Shows what is currently set |

It writes exactly the values listed under "Install from a Windows 11 ISO" and nothing else: no services, no startup entries, no files inside Windows. The whole file is plain, readable batch code. Set `T2F_DRYRUN=1` first if you want it to print the commands instead of running them.

## What the tool does and doesn't do

The same summary is inside the tool under **About this tool**.

- It asks before every change to your system: setting registry values, mounting the ISO, starting Setup, installing a package and restarting.
- It shows the exact web address and asks before opening Microsoft's download pages. It never downloads files by itself.
- It keeps a log of everything it does (see "The log" below).
- It does not install any software, add startup entries or run in the background, and it contains no encoded or hidden commands.
- It calls two documented Windows functions directly: `kernel32!IsProcessorFeaturePresent` for the SSE4.2 check and `kernel32!GetFirmwareType` to tell UEFI from Legacy BIOS. Everything else is standard PowerShell and Windows Forms.
- The launcher starts the script with `-ExecutionPolicy Bypass` for that one PowerShell window only. Your system's execution policy is not changed.

## The log

Every run writes its own log file to a `Logs` folder next to the tool, named with the date and time, for example `Tips2Fix_2026-09-30_15-07-31.log`. A second run never overwrites the first, and only the newest 20 files are kept.

It records the screens you opened, the buttons you pressed, every decision you made, the registry values written or removed, and whatever `DISM`, `mountvol` and the patcher printed, so a problem can be traced afterwards. It also records the web addresses it offered to open. It does not contain your user name or computer name, and nothing in it is sent anywhere.

If the tool's own folder cannot be written to (a read-only location, for example), it uses `%LOCALAPPDATA%\Tips2Fix\Logs` instead. **About this tool** has buttons that open the current log and its folder. `Bypass-Requirements.cmd` keeps a one-line-per-run history in its own `Logs` folder when used on its own.

## How it works

- **Elevation:** a UAC prompt when the tool starts. Nothing is elevated silently.
- **CPU check:** `IsProcessorFeaturePresent(38)`, which is `PF_SSE4_2_INSTRUCTIONS_AVAILABLE`. If that call fails, it falls back to a guess based on the CPU name.
- **Windows version:** `CurrentBuildNumber` from `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion`. Windows 10 22H2 is 19045, 23H2 is 22631, 24H2 is 26100, 25H2 is 26200 and 26H2 is 26300.
- **Edition and language:** `EditionID` from the same key, and the Windows display language. `ProductName` is not used because it still says "Windows 10" on Windows 11.
- **ISO:** mounted with `Mount-DiskImage` and always unmounted when the tool closes.
- **ISO details:** the build from `sources\idwbinfo.txt`, languages from `sources\lang.ini` and editions from `Get-WindowsImage`.
- **Extraction:** `robocopy /E /MT:8`. Exit codes 0 to 7 mean success, 8 and above mean failure.
- **Setup:** `sources\setupprep.exe`, or `setup.exe` if that is missing, started from its own folder.
- **Enablement package:** `DISM /Online /Add-Package /Quiet /NoRestart`. Exit code 3010 means it worked and a restart is needed.

## Troubleshooting

**"Keep personal files and apps" is grayed out**

This is almost never a hardware problem:

- **Language mismatch.** The ISO must be in the same language as your Windows. This is the most common cause.
- **Edition mismatch.** Home to Home, Pro to Pro. Check with `winver`.
- **You used the `/product server` retry.** It grays this option out. Cancel Setup and run the tool again without the retry.
- **You started Setup from a USB stick.** Start it from inside Windows instead.

**"This PC can't run Windows 11" still appears**

- Make sure you clicked **Apply** when the tool asked about the registry values.
- Restart the PC once and run the tool again.
- If it still fails, use **Setup was blocked - retry** in the tool's Setup window, after reading the warning.
- On work or school PCs, policies can lock these registry keys.

**The enablement package won't install**

- Check step 1 on that screen. If it says `KB5120998` is missing, install it through Windows Update or from the Update Catalog, then try again.
- Make sure you downloaded the x64 package (or arm64 on an ARM PC). The screen marks the one your PC needs.

**The ISO won't mount or gets no drive letter**

- Wait 5 to 10 seconds. External drives can be slow.
- Check that the ISO opens when you double-click it in File Explorer.
- Other virtual drive programs can get in the way. Try closing them.

**Not enough free space**

- Choose **Run straight from the mounted ISO** instead of extracting. It needs no extra space. If you picked extraction and the drive is too full, the tool offers this switch for you.

**"Setup files not found"**

- The ISO may be damaged or modified. Check that it contains `sources\setupprep.exe` or `setup.exe`, or download it again.

**Windows warns that the file came from the internet**

- Right-click the downloaded ZIP, choose **Properties**, tick **Unblock**, click **OK**, and extract it again.

## Verify your download

```powershell
Get-FileHash .\Windows11_QuickInstaller.ps1 -Algorithm SHA256
Get-FileHash .\Run-Installer.bat -Algorithm SHA256
```

Compare the results with the hashes published with the release.

## Privacy

- The tool does not collect or send any personal data.
- No telemetry, analytics or background services.
- The only network activity is opening web pages in your browser, and only when you click.

## Disclaimer

Installing Windows 11 on unsupported hardware puts your PC in a configuration Microsoft does not support. Microsoft does not guarantee compatibility, drivers or support, and may hold back updates from unsupported PCs. Use this tool at your own risk and back up your files first.

## Credits

Tips2Fix, author and maintainer.

## Downloads

| Version | Released | Windows | Download |
|---|---|---|---|
| **v1.2.0** (latest) | 2026-10-01 | 26H2 | [Tips2Fix-Windows11-Installer-1.2.0.zip](https://github.com/tips2fix/Tips2Fix-Windows11-Installer/releases/download/1.2.0/Tips2Fix-Windows11-Installer-1.2.0.zip) |
| v1.0.2 | 2025-10-07 | 25H2 | [Tips2Fix-Windows11-Installer-1.0.2.zip](https://github.com/tips2fix/Tips2Fix-Windows11-Installer/releases/download/1.0.2/Tips2Fix-Windows11-Installer-1.0.2.zip) |
| v1.0.1 | 2025-10-01 | 25H2 | [Tips2Fix-Windows11-Installer-1.0.1.zip](https://github.com/tips2fix/Tips2Fix-Windows11-Installer/releases/download/1.0.1/Tips2Fix-Windows11-Installer-1.0.1.zip) |
