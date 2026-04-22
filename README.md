# fitgrab

> **FitGirl Repacks downloader via FuckingFast mirrors**

fitgrab automates downloading FitGirl repacks by extracting direct FuckingFast CDN links and downloading at full speed.

## What it does

fitgrab is a Python tool that:

1. **Scrapes FitGirl game pages** to find FuckingFast mirror links
2. **Decrypts PrivateBin pastes** (client-side AES encryption) using Playwright
3. **Resolves FuckingFast URLs** to direct CDN links with rate-limit bypass
4. **Downloads files** using aria2c with resume support
5. **Tests archives** for integrity with unrar

**Pipeline:**
```
FitGirl page
    [Stage 1] Scrapes PrivateBin paste URL
         |
         v
PrivateBin paste
    [Stage 2] Decrypts AES-encrypted links via Playwright
         |
         v
FuckingFast pages
    [Stage 3] Resolves CDN URLs with rate-limit bypass
         |
         v
aria2c
    [Stage 4] Downloads at full speed with resume support
         |
         v
Your disk
    [Stage 5] Tests archive integrity
```

---

## Features

- **Full-speed downloads**: aria2c with 15 concurrent connections
- **Resume support**: Interrupted? Re-run and pick up where you left off
- **Rate-limit bypass**: Exponential backoff + UA rotation + worker cooldown
- **Beautiful TUI**: Rich terminal UI with progress bars and status panels
- **Cross-platform**: Windows 10/11 and Linux (Ubuntu, Fedora, Arch, etc.)
- **Headless automation**: Playwright Chromium runs invisibly
- **Integrity testing**: Automatic unrar test on completion

---

## Quick Start

### One-Liner Installation

**Linux:**
```bash
curl -fsSL https://raw.githubusercontent.com/abdoumarkaba/fitgrab/main/install_linux.sh | bash
```
*Script will prompt for sudo when needed.*

**Windows (PowerShell): Run as Administrator**
```powershell
Invoke-WebRequest -Uri https://raw.githubusercontent.com/abdoumarkaba/fitgrab/main/install_windows.ps1 -OutFile install.ps1; ./install.ps1
```

### Linux

```bash
# Or install from local script
./install_linux.sh

# Download a game
fitgrab https://fitgirl-repacks.site/god-of-war-ragnarok/ --dir ~/Games

# Or with a direct paste URL
fitgrab https://paste.fitgirl-repacks.site/?abc#xyz --dir ~/Games

# Dry run (preview what will be downloaded)
fitgrab <url> --dry-run
```

### Windows

```powershell
# Run the installation script (PowerShell)
.\install_windows.ps1

# Download a game
python fitgrab https://fitgirl-repacks.site/stellar-blade/ --dir C:\Games

# Or use the batch wrapper
fitgrab.bat https://fitgirl-repacks.site/stellar-blade/ --dir C:\Games

# Dry run
python fitgrab <url> --dry-run
```

---

## Installation

### Prerequisites

- **Python 3.8+** - [Download](https://www.python.org/downloads/)
- **aria2** - Download manager (auto-installed by scripts)
- **unrar** - Archive tester (optional, auto-installed by scripts)

### Automated Installation

#### Linux (Ubuntu/Debian/Fedora/Arch/openSUSE)

```bash
# Make the script executable
chmod +x install_linux.sh

# Run it
./install_linux.sh
```

The script will:
1. Detect your Linux distribution
2. Install aria2 and unrar via package manager
3. Install Python dependencies (playwright, playwright-stealth, rich)
4. Install Playwright Chromium browser
5. Make fitgrab executable

#### Windows (PowerShell)

```powershell
# Right-click > Run with PowerShell
.\install_windows.ps1
```

The script will:
1. Check for Python installation
2. Install aria2 via winget or manual download
3. Install unrar (WinRAR/7-Zip)
4. Install Python dependencies
5. Install Playwright Chromium browser
6. Create fitgrab.bat wrapper

### Manual Installation

If automated scripts fail, install manually:

```bash
# System dependencies
# Ubuntu/Debian
sudo apt install aria2 unrar python3-pip

# Fedora/RHEL
sudo dnf install aria2 unrar python3-pip

# Arch
sudo pacman -S aria2 unrar python-pip

# Python dependencies
pip install playwright playwright-stealth rich

# Playwright browser
playwright install chromium
```

Windows:
```powershell
# Install Python from https://www.python.org/downloads/
# Install aria2 from https://github.com/aria2/aria2/releases
# Install WinRAR from https://www.rarlab.com/download.htm

pip install playwright playwright-stealth rich
python -m playwright install chromium
```

---

## Usage

```bash
fitgrab <url> [options]
```

### Arguments

- `<url>` - FitGirl game page URL or direct PrivateBin paste URL

### Options

- `--dir <path>` - Download directory (default: auto-detected)
- `--dry-run` - Preview download without actually downloading
- `--concurrency <n>` - Parallel browser contexts for URL resolution (default: 2)

### Examples

```bash
# Basic download
fitgrab https://fitgirl-repacks.site/cyberpunk-2077/

# Custom directory
fitgrab https://fitgirl-repacks.site/elden-ring/ --dir ~/Games/FromSoft

# Direct paste URL (skip game page scraping)
fitgrab https://paste.fitgirl-repacks.site/?abc123#xyz789 --dir ~/Games

# Preview before downloading
fitgrab https://fitgirl-repacks.site/horizon-zero-dawn/ --dry-run

# Increase concurrency (faster URL resolution, more CPU)
fitgrab https://fitgirl-repacks.site/gta-v/ --concurrency 4
```

### Resume Interrupted Downloads

If fitgrab is interrupted (Ctrl+C or crash), simply re-run the same command:

```bash
fitgrab https://fitgirl-repacks.site/some-game/ --dir ~/Games
```

fitgrab will:
1. Detect existing files
2. Skip completed downloads
3. Resume incomplete downloads
4. Clean corrupted state

---

## How It Works

### Stage 1: FitGirl Page Scraping
Loads the FitGirl game page and finds the "Filehoster: FuckingFast" anchor, extracting the PrivateBin paste URL.

### Stage 2: PrivateBin Decryption
PrivateBin uses client-side AES encryption. The decryption key is in the URL fragment (`#key`). Playwright executes the JavaScript, waits for decryption, and extracts the FuckingFast download links.

### Stage 3: URL Resolution
Each FuckingFast page requires interaction to reveal the CDN URL:
1. Click download button (opens ad popup)
2. Close popup
3. Click again to trigger actual download
4. Capture URL via `expect_download()` and cancel
5. aria2c handles the actual bytes

**Rate-limit bypass:**
- Per-context UA + viewport rotation (each tab looks like a different visitor)
- Full-jitter exponential backoff (spreads retry load)
- Persistent retry queue with attempt counters
- Worker cooldown on hard 429s

### Stage 4: aria2c Download
15 concurrent files × 1 connection each. Resume-safe via `.aria2` control files.

### Stage 5: Archive Testing
Runs `unrar t` on the first part to verify integrity.

---

## Troubleshooting

### "Playwright browsers not found"

```bash
playwright install chromium
```

### "aria2c not found"

**Linux:**
```bash
sudo apt install aria2  # Ubuntu/Debian
sudo dnf install aria2  # Fedora
sudo pacman -S aria2    # Arch
```

**Windows:** Install from https://github.com/aria2/aria2/releases

### "unrar not found" (optional)

**Linux:**
```bash
sudo apt install unrar  # Ubuntu/Debian
sudo dnf install unrar  # Fedora
sudo pacman -S unrar    # Arch
```

**Windows:** Install WinRAR or 7-Zip

### Download stuck at "Resolving URLs"

- FuckingFast may be rate-limiting. Wait and re-run.
- Try decreasing `--concurrency` to 1
- Check your internet connection

### "Failed to read from the segment file"

Corrupted aria2 state. Re-run fitgrab - it will clean up automatically.

### Windows: "python is not recognized"

Install Python from https://www.python.org/downloads/ and check "Add Python to PATH" during installation.

---

## Technical Details

### Rate-Limit Bypass Strategy

FuckingFast's CDN uses a sliding window rate limit. fitgrab employs:

- **UA rotation**: 7 different user-agents, randomized per context
- **Viewport randomization**: 1280-1920px width, 720-1080px height
- **Full-jitter backoff**: `random(0, min(3 * 2^attempt, 60))` seconds
- **Cooldown on 429**: 60s + random(0, 30s) worker pause
- **Persistent retry queue**: Failed URLs re-enter with incremented attempt counter

### aria2c Configuration

- `split=1`: Single connection per file (FuckingFast doesn't support Range headers properly)
- `max-concurrent-downloads=15`: Parallel file downloads
- `continue=true`: Resume support
- `file-allocation=none`: Skip pre-allocation (faster on SSD)
- `timeout=60`: Detect stalled connections

### Browser Persistence

Playwright browsers are stored in `~/.local/share/playwright-browsers` to survive system cache cleaning.

---

## Performance Tips

- **SSD**: Use SSD for download directory (faster file allocation)
- **Bandwidth**: fitgrab saturates any connection up to 1 Gbps
- **CPU**: Stage 3 (URL resolution) benefits from more cores (increase `--concurrency`)
- **RAM**: Minimal impact (< 500MB even with 15 concurrent downloads)

---

## License

MIT License - use freely, modify as needed.

---

## Contributing

Issues, PRs, and improvements welcome! This is a community tool for gamers.

---

## Disclaimer

This tool is for educational purposes and personal use only. Respect copyright laws in your jurisdiction. The author is not affiliated with FitGirl Repacks or FuckingFast.
