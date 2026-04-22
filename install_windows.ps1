# fitgrab Windows Installation Script
# Requires PowerShell 5.1+ (Windows 10/11)

# ── Helper Functions ─────────────────────────────────────────────────────────────

# Retry function with exponential backoff
function Retry-Command {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxAttempts = 3,
        [int]$InitialDelay = 1
    )

    $attempt = 1
    $delay = $InitialDelay

    while ($attempt -le $MaxAttempts) {
        try {
            & $ScriptBlock
            return $true
        }
        catch {
            if ($attempt -eq $MaxAttempts) {
                Write-Host "  ERROR: Command failed after $MaxAttempts attempts: $_" -ForegroundColor Red
                return $false
            }
            Write-Host "  Attempt $attempt/$MaxAttempts failed. Retrying in ${delay}s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $delay
            $delay = $delay * 2
            $attempt++
        }
    }
    return $false
}

# Check if command exists
function Test-Command {
    param([string]$Name)
    $null = Get-Command $Name -ErrorAction SilentlyContinue
    return $?
}

# Check Python version meets minimum requirement
function Test-PythonVersion {
    param([string]$PythonExe)
    $version = & $PythonExe --version 2>&1
    if ($version -match 'Python (\d+)\.(\d+)') {
        $major = [int]$matches[1]
        $minor = [int]$matches[2]
        if ($major -lt 3 -or ($major -eq 3 -and $minor -lt 8)) {
            Write-Host "  ERROR: Python $version is too old. Need Python 3.8 or higher." -ForegroundColor Red
            return $false
        }
    }
    return $true
}

# Check available disk space (in MB)
function Test-DiskSpace {
    $requiredMB = 500
    $drive = $env:SystemDrive
    $driveInfo = Get-PSDrive -Name $drive.Substring(0,1)
    $freeMB = [math]::Floor($driveInfo.Free / 1MB)

    if ($freeMB -lt $requiredMB) {
        Write-Host "  ERROR: Insufficient disk space. Need ${requiredMB}MB, have ${freeMB}MB available." -ForegroundColor Red
        return $false
    }
    return $true
}

# Check PowerShell execution policy
function Test-ExecutionPolicy {
    $policy = Get-ExecutionPolicy -Scope CurrentUser
    if ($policy -eq 'Restricted' -or $policy -eq 'Undefined') {
        Write-Host "  WARNING: PowerShell execution policy is $policy" -ForegroundColor Yellow
        Write-Host "  Some operations may fail. Consider running: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Yellow
        return $false
    }
    return $true
}

# Check network connectivity
function Test-Network {
    try {
        $response = Test-NetConnection -ComputerName github.com -Port 443 -InformationLevel Quiet -ErrorAction Stop
        if (-not $response) {
            Write-Host "  ERROR: Cannot reach GitHub. Please check your internet connection." -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host "  ERROR: Network check failed: $_" -ForegroundColor Red
        return $false
    }
    return $true
}

# ── Pre-flight Checks ───────────────────────────────────────────────────────────

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  fitgrab Installation for Windows" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Running pre-flight checks..." -ForegroundColor Green
Write-Host ""

# Check network
if (-not (Test-Network)) {
    exit 1
}

# Check disk space
if (-not (Test-DiskSpace)) {
    exit 1
}

# Check execution policy
Test-ExecutionPolicy

Write-Host "Pre-flight checks passed." -ForegroundColor Green
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "WARNING: Not running as Administrator." -ForegroundColor Yellow
    Write-Host "Some installations may fail. Re-run as Administrator." -ForegroundColor Yellow
    Write-Host ""
}

# Check if Python is installed
Write-Host "Checking for Python..." -ForegroundColor Green
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
$python3Cmd = Get-Command python3 -ErrorAction SilentlyContinue

if ($pythonCmd) {
    $pythonExe = $pythonCmd.Source
    Write-Host "Found Python: $pythonExe" -ForegroundColor Green
} elseif ($python3Cmd) {
    $pythonExe = $python3Cmd.Source
    Write-Host "Found Python3: $pythonExe" -ForegroundColor Green
} else {
    Write-Host "ERROR: Python is not installed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install Python 3.8 or higher from:" -ForegroundColor Yellow
    Write-Host "https://www.python.org/downloads/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "During installation, check 'Add Python to PATH'" -ForegroundColor Yellow
    exit 1
}

# Check Python version
if (-not (Test-PythonVersion -PythonExe $pythonExe)) {
    exit 1
}

$pythonVersion = & $pythonExe --version 2>&1
Write-Host "Python version: $pythonVersion" -ForegroundColor Green
Write-Host ""

# Install aria2
Write-Host "Installing aria2..." -ForegroundColor Green
if (Test-Command aria2c) {
    Write-Host "aria2 already installed." -ForegroundColor Green
} else {
    Write-Host "Downloading aria2 installer..." -ForegroundColor Yellow

    # Use winget if available (Windows 11 and newer Windows 10)
    if (Test-Command winget) {
        Write-Host "Using winget to install aria2..." -ForegroundColor Yellow
        if (-not (Retry-Command -ScriptBlock { winget install aria2 --accept-source-agreements --accept-package-agreements })) {
            Write-Host "ERROR: Failed to install aria2 via winget" -ForegroundColor Red
            exit 1
        }
    } else {
        # Fallback: download aria2 manually
        $aria2Url = "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip"
        $aria2Zip = "$env:TEMP\aria2.zip"
        $aria2Dir = "$env:LOCALAPPDATA\aria2"

        Write-Host "Downloading aria2 from GitHub..." -ForegroundColor Yellow
        try {
            if (-not (Retry-Command -ScriptBlock { Invoke-WebRequest -Uri $aria2Url -OutFile $aria2Zip -UseBasicParsing })) {
                Write-Host "ERROR: Failed to download aria2" -ForegroundColor Red
                exit 1
            }

            Write-Host "Extracting aria2..." -ForegroundColor Yellow
            try {
                Expand-Archive -Path $aria2Zip -DestinationPath $aria2Dir -Force -ErrorAction Stop
            }
            catch {
                Write-Host "ERROR: Failed to extract aria2 (corrupted download or disk space)" -ForegroundColor Red
                Remove-Item $aria2Zip -Force -ErrorAction SilentlyContinue
                exit 1
            }

            # Add aria2 to PATH
            $aria2Bin = "$aria2Dir\aria2-1.37.0-win-64bit-build1"
            $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($currentPath -notlike "*$aria2Bin*") {
                [Environment]::SetEnvironmentVariable("Path", "$currentPath;$aria2Bin", "User")
                Write-Host "Added aria2 to user PATH." -ForegroundColor Green
                Write-Host "You may need to restart your terminal for PATH changes to take effect." -ForegroundColor Yellow
            }

            Remove-Item $aria2Zip -Force
        }
        catch {
            Write-Host "ERROR: aria2 installation failed: $_" -ForegroundColor Red
            Remove-Item $aria2Zip -Force -ErrorAction SilentlyContinue
            exit 1
        }
    }

    # Validate aria2 installation
    if (-not (Test-Command aria2c)) {
        Write-Host "ERROR: aria2 installed but not in PATH" -ForegroundColor Red
        exit 1
    }

    Write-Host "aria2 installed successfully." -ForegroundColor Green
}
Write-Host ""

# Install unrar
Write-Host "Installing unrar..." -ForegroundColor Green
if (Test-Command unrar) {
    Write-Host "unrar already installed." -ForegroundColor Green
} else {
    Write-Host "Downloading unrar..." -ForegroundColor Yellow

    # Use winget if available
    if (Test-Command winget) {
        Write-Host "Using winget to install unrar..." -ForegroundColor Yellow
        if (-not (Retry-Command -ScriptBlock { winget install RARLab.WinRAR --accept-source-agreements --accept-package-agreements })) {
            Write-Host "WARNING: Failed to install unrar via winget" -ForegroundColor Yellow
            Write-Host "Please install WinRAR or 7-Zip manually:" -ForegroundColor Yellow
            Write-Host "WinRAR: https://www.rarlab.com/download.htm" -ForegroundColor Cyan
            Write-Host "7-Zip: https://www.7-zip.org/download.html" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "unrar is optional but recommended for archive testing." -ForegroundColor Yellow
        } else {
            # Validate unrar installation
            if (Test-Command unrar) {
                Write-Host "unrar installed successfully." -ForegroundColor Green
            } else {
                Write-Host "WARNING: unrar installed but not in PATH" -ForegroundColor Yellow
            }
        }
    } else {
        # Fallback: provide manual instructions
        Write-Host "Please install WinRAR or 7-Zip manually:" -ForegroundColor Yellow
        Write-Host "WinRAR: https://www.rarlab.com/download.htm" -ForegroundColor Cyan
        Write-Host "7-Zip: https://www.7-zip.org/download.html" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "After installation, ensure 'unrar' is in your PATH." -ForegroundColor Yellow
        Write-Host "unrar is optional but recommended for archive testing." -ForegroundColor Yellow
    }
}
Write-Host ""

# Install Python dependencies
Write-Host "Installing Python dependencies..." -ForegroundColor Green

# Check if pip is available
$pipCmd = Get-Command pip -ErrorAction SilentlyContinue
$pip3Cmd = Get-Command pip3 -ErrorAction SilentlyContinue

if ($pipCmd) {
    $pipExe = $pipCmd.Source
} elseif ($pip3Cmd) {
    $pipExe = $pip3Cmd.Source
} else {
    Write-Host "pip not found. Installing ensurepip..." -ForegroundColor Yellow
    if (-not (Retry-Command -ScriptBlock { & $pythonExe -m ensurepip --upgrade })) {
        Write-Host "ERROR: Failed to install pip" -ForegroundColor Red
        exit 1
    }
    $pipExe = "$($pythonExe -replace 'python\.exe$', 'Scripts\pip.exe')"
}

Write-Host "Using pip: $pipExe" -ForegroundColor Green

# Install from requirements.txt if available
if (Test-Path "requirements.txt") {
    Write-Host "Installing from requirements.txt..." -ForegroundColor Yellow
    if (-not (Retry-Command -ScriptBlock { & $pipExe install -r requirements.txt })) {
        Write-Host "ERROR: Failed to install Python packages" -ForegroundColor Red
        Write-Host "Try: pip install playwright playwright-stealth rich" -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Host "Installing packages individually..." -ForegroundColor Yellow
    if (-not (Retry-Command -ScriptBlock { & $pipExe install playwright playwright-stealth rich })) {
        Write-Host "ERROR: Failed to install Python packages" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Python dependencies installed successfully." -ForegroundColor Green
Write-Host ""

# Install Playwright browsers
Write-Host "Installing Playwright Chromium browser..." -ForegroundColor Green
if (-not (Retry-Command -ScriptBlock { & $pythonExe -m playwright install chromium })) {
    Write-Host "ERROR: Failed to install Playwright browsers" -ForegroundColor Red
    Write-Host "Try running: python -m playwright install chromium" -ForegroundColor Yellow
    exit 1
}

Write-Host "Playwright Chromium installed successfully." -ForegroundColor Green
Write-Host ""

# Create batch file wrapper for fitgrab
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (Test-Path "$scriptDir\fitgrab") {
    $batchContent = @"
@echo off
python "$scriptDir\fitgrab" %*
"@
    $batchPath = "$scriptDir\fitgrab.bat"
    $batchContent | Out-File -FilePath $batchPath -Encoding ASCII
    Write-Host "Created fitgrab.bat wrapper." -ForegroundColor Green
}

# ── Post-installation Validation ──────────────────────────────────────────────

Write-Host ""
Write-Host "Validating installation..." -ForegroundColor Green
Write-Host ""

# Validate aria2c
if (Test-Command aria2c) {
    Write-Host "  ✓ aria2c installed and working" -ForegroundColor Green
} else {
    Write-Host "  ✗ aria2c validation failed" -ForegroundColor Red
    exit 1
}

# Validate unrar (optional)
if (Test-Command unrar) {
    Write-Host "  ✓ unrar installed and working" -ForegroundColor Green
} else {
    Write-Host "  ⚠ unrar not found (optional for archive testing)" -ForegroundColor Yellow
}

# Validate Python packages
try {
    & $pythonExe -c "import playwright" 2>&1 | Out-Null
    Write-Host "  ✓ playwright installed" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ playwright validation failed" -ForegroundColor Red
    exit 1
}

try {
    & $pythonExe -c "import rich" 2>&1 | Out-Null
    Write-Host "  ✓ rich installed" -ForegroundColor Green
}
catch {
    Write-Host "  ⚠ rich not found (optional for beautiful TUI)" -ForegroundColor Yellow
}

# Validate fitgrab
if (Test-Path "$scriptDir\fitgrab") {
    try {
        & $pythonExe "$scriptDir\fitgrab" --help 2>&1 | Out-Null
        Write-Host "  ✓ fitgrab installed and working" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ fitgrab validation failed" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  ⚠ fitgrab not found in $scriptDir" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "All validations passed." -ForegroundColor Green
Write-Host ""

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Installation Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "To run fitgrab:" -ForegroundColor Green
Write-Host "  python fitgrab <fitgirl-url> --dir C:\Games" -ForegroundColor Cyan
Write-Host "  OR" -ForegroundColor Cyan
Write-Host "  fitgrab.bat <fitgirl-url> --dir C:\Games" -ForegroundColor Cyan
Write-Host ""
Write-Host "Example:" -ForegroundColor Green
Write-Host "  python fitgrab https://fitgirl-repacks.site/god-of-war-ragnarok/ --dir C:\Games" -ForegroundColor Cyan
Write-Host ""
Write-Host "For more info: python fitgrab --help" -ForegroundColor Cyan
Write-Host ""
Write-Host "NOTE: If you modified PATH, restart your terminal." -ForegroundColor Yellow
Write-Host ""
