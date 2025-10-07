# 🚀 Tips2Fix Windows 11 25H2 Installer 
# Safe Confirmed Edition ✅

A friendly, consent‑driven helper to launch the **Windows 11 25H2** setup on unsupported PCs — with clear UI, live progress, and **antivirus‑friendly** behavior.  
Built by **Tips2Fix** in collaboration with **ChatGPT** (Tips2Fix Project).

---
## ✨ Highlights

- **Three modes**:  
  1) **Fast** – no registry changes.  
  2) **Advanced** – applies *only on consent* the well‑known LabConfig/MoSetup keys (TPM / CPU / RAM / Secure Boot bypass).  
  3) **Reset** – removes those keys and restores defaults.
- **ISO → Desktop extraction** with a **live progress bar** (no obfuscation, no hidden windows).
- **User consent for everything** (extraction, registry edits, setup start, optional YouTube open).
- **Clear logs** written to your Desktop: `Tips2Fix_W11_install_log.txt`.
- **No persistence, no background tasks, no network calls** (except optional YouTube, on consent).

> This project keeps the original UI layout (orange title & footer) you saw in the video, so users won’t be surprised by a different interface.

---
## 📦 What’s in this folder

- `Run-Installer.bat` — launcher that elevates if needed and starts the PowerShell script.  
- `Windows11_QuickInstaller.ps1` — the main guided installer (WinForms UI).  
- `README.md` — this file.

> Keep both `.bat` and `.ps1` in the **same folder**.

---

## 🖥 Requirements

- Windows 10 or later
- Administrator rights (UAC prompt will appear)
- Windows PowerShell **5.1** (built-in on Windows 10+)
- A **Windows 11 25H2 ISO** file

> Recommended: a good backup before you start. Installing on unsupported hardware is at your own risk.

---
## 🚀 Quick Start

1. **Download** this folder (or clone) and unzip it somewhere local.  
2. **Right‑click** `Run-Installer.bat` → **Run as administrator**.  
3. Pick your **Windows 11 25H2 ISO**.  
4. Choose mode: **Fast**, **Advanced**, or **Reset**.  
5. Confirm extraction location (defaults to **Desktop\\\<ISO name>**).  
6. After extraction, confirm **Start Setup**.  
7. (Optional) After launch, you may be asked whether to open the **Tips2Fix YouTube** channel.

When Windows installation is completely finished, you can **safely delete** the extracted folder from your Desktop.

---
## 🧭 Modes explained

### 1) Fast (no registry edits)
- Extracts ISO to `Desktop\<ISO name>`.
- Launches the official **Windows Setup** from the extracted files.
- Good for supported or near‑supported hardware.

### 2) Advanced (apply bypass keys on consent)
- Creates these keys (DWORD = 1) to relax checks during setup:
  - `HKLM\SYSTEM\Setup\LabConfig\BypassTPMCheck`
  - `HKLM\SYSTEM\Setup\LabConfig\BypassSecureBootCheck`
  - `HKLM\SYSTEM\Setup\LabConfig\BypassRAMCheck`
  - `HKLM\SYSTEM\Setup\LabConfig\BypassCPUCheck`
  - `HKLM\SYSTEM\Setup\MoSetup\AllowUpgradesWithUnsupportedTPMOrCPU`
- Asks **before** applying anything.
- You can run **Reset** later to remove them.

### 3) Reset (restore defaults)
- Deletes `HKLM\SYSTEM\Setup\LabConfig` (if present).  
- Deletes the `AllowUpgradesWithUnsupportedTPMOrCPU` value under `HKLM\SYSTEM\Setup\MoSetup` (if present).

> All registry operations are **visible and logged**; nothing is hidden.

---
## 🔐 Antivirus‑friendly design

- **Consent‑first**: every sensitive step has a clear **Yes/No** prompt.  
- **No obfuscation or encoded commands**; no AMSI tampering; no persistence.  
- **Local file operations only** (ISO mount + copy), using standard Windows tools.  
- **Optional** network action (open YouTube) only **after** user confirmation.  
- **Logging** to a visible Desktop text file.
- Supports running with Execution Policy **RemoteSigned** or **AllSigned** for best results (see below).

### Code signing & Execution Policy (recommended)

- If you can **code‑sign** the PS1, the BAT will happily run under `AllSigned` (most AV‑friendly).  
- If unsigned, the launcher can **prompt to Unblock** the PS1 so it can run under `RemoteSigned`.  
- You can also run with `Bypass`, but some AVs score that higher heuristically.

---
## 🧰 How it works (technical)

- **Elevation**: via UAC on demand; the BAT/PS1 do not force elevation silently.  
- **ISO**: mounted via `Mount-DiskImage`.  
- **Extraction**: deterministic `Copy-Item` with a **live progress bar** (WinForms).  
- **Setup**: prefers `sources\setupprep.exe`, falling back to `setup.exe`.  
- **Arguments**: launches with `/product server` to allow the GUI install flow.  
- **Logs**: `Desktop\Tips2Fix_W11_install_log.txt` with timestamps.

---
## 🧪 Troubleshooting

**Mount failed or no drive letter appears**  
- Wait ~5–10 seconds; external drives can be slow to enumerate.  
- Ensure the ISO opens normally by double‑clicking in File Explorer.  
- Some 3rd‑party virtual‑drive tools can interfere — try disabling them.

**Extraction seems stuck or very slow**  
- Large ISOs on slow HDDs can take time; the progress bar uses real file counts.  
- Make sure you have enough free space on Desktop (same drive as `%USERPROFILE%`).

**“Setup files not found” after extraction**  
- Check that `Desktop\<ISO name>\sources\setupprep.exe` (or `setup.exe`) exists.  
- If your ISO is modified/trimmed, mount it again and verify its structure.

**Registry bypass didn’t stick**  
- You may have chosen **Fast** mode. Run the tool again and select **Advanced**.  
- Corporate policies can lock those keys; try again as full Admin.

**SmartScreen/AV warning**  
- Prefer **signed** scripts and run under `AllSigned`/`RemoteSigned` (no Bypass).  
- Keep files unmodified after signing (changing file contents invalidates the signature).

---
## 🔍 Verify downloads (optional but recommended)

You can compute a checksum after download:

```powershell
Get-FileHash .\Windows11_QuickInstaller.ps1 -Algorithm SHA256
Get-FileHash .\Run-Installer.bat -Algorithm SHA256
```

Compare the hashes with the published values (if you distribute releases).

---
## 🔒 Privacy

- The tool does **not** collect or transmit personal data.  
- No telemetry, analytics, or background services.

---
## 🙌 Credits

- **Tips2Fix** — author & maintainer.  
- **ChatGPT** — collaborator on UI polish and safety flow wording.


<p align="center">
  <img src="https://raw.githubusercontent.com/yourusername/Tips2Fix/main/logo.png" width="160" alt="Tips2Fix Logo"/>
</p>

<h1 align="center">💻 Tips2Fix Windows 11 25H2 Installer</h1>

<p align="center">
  A clean, safe and user-friendly PowerShell installer that lets you upgrade or install Windows 11 25H2 
  on <b>any PC</b> — even unsupported ones — with full transparency and no hacks.
</p>

---

## ⚙️ Overview

**Tips2Fix Windows 11 25H2 Installer** is a lightweight and open-source tool designed to help you:
- ✅ Install or upgrade to **Windows 11 25H2** on unsupported CPUs, no TPM, no Secure Boot.
- 💾 Run directly from your Desktop — no setup, no background services.
- 🧩 Choose between **Fast**, **Advanced**, or **Reset** install modes.
- 🪟 Built in **PowerShell + WinForms** with a modern orange-accent UI.

Everything happens locally, with user consent at each step — **no obfuscation, no hidden tasks, no telemetry**.

---

## 🚀 Download the Installer Zip

| Version | Release Date | Download |
|----------|---------------|-----------|
| 🟢 **v1.0.2** | 2025-10-07 | [⬇️ Download ZIP](https://github.com/tips2fix/Tips2Fix-Windows11-Installer/releases/download/1.0.2/Tips2Fix-Windows11-Installer-1.0.2.zip) |
| 🟠 **v1.0.1** | 2025-10-06 | [⬇️ Download ZIP](https://github.com/tips2fix/Tips2Fix-Windows11-Installer/releases/download/1.0.1/Tips2Fix-Windows11-Installer-1.0.1.zip) |
| ⚪ **v1.0.0** | 2025-10-05 | [⬇️ Download ZIP](https://github.com/tips2fix/Tips2Fix-Windows11-Installer/releases/download/1.0.1/Tips2Fix-Windows11-Installer.zip) |






