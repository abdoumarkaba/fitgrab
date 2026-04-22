# fitgrab Windows Installation Script
# Requires PowerShell 5.1+ (Windows 10/11)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  fitgrab Installation for Windows" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
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
$pythonVersion = & $pythonExe --version 2>&1
Write-Host "Python version: $pythonVersion" -ForegroundColor Green
Write-Host ""

# Install aria2
Write-Host "Installing aria2..." -ForegroundColor Green
if (Get-Command aria2c -ErrorAction SilentlyContinue) {
    Write-Host "aria2 already installed." -ForegroundColor Green
} else {
    Write-Host "Downloading aria2 installer..." -ForegroundColor Yellow
    
    # Use winget if available (Windows 11 and newer Windows 10)
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Using winget to install aria2..." -ForegroundColor Yellow
        winget install aria2 --accept-source-agreements --accept-package-agreements
    } else {
        # Fallback: download aria2 manually
        $aria2Url = "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip"
        $aria2Zip = "$env:TEMP\aria2.zip"
        $aria2Dir = "$env:LOCALAPPDATA\aria2"
        
        Write-Host "Downloading aria2 from GitHub..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $aria2Url -OutFile $aria2Zip -UseBasicParsing
        
        Write-Host "Extracting aria2..." -ForegroundColor Yellow
        Expand-Archive -Path $aria2Zip -DestinationPath $aria2Dir -Force
        
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
    
    Write-Host "aria2 installed successfully." -ForegroundColor Green
}
Write-Host ""

# Install unrar
Write-Host "Installing unrar..." -ForegroundColor Green
if (Get-Command unrar -ErrorAction SilentlyContinue) {
    Write-Host "unrar already installed." -ForegroundColor Green
} else {
    Write-Host "Downloading unrar..." -ForegroundColor Yellow
    
    # Use winget if available
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Using winget to install unrar..." -ForegroundColor Yellow
        winget install RARLab.WinRAR --accept-source-agreements --accept-package-agreements
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
    & $pythonExe -m ensurepip --upgrade
    $pipExe = "$($pythonExe -replace 'python\.exe$', 'Scripts\pip.exe')"
}

Write-Host "Using pip: $pipExe" -ForegroundColor Green

# Install from requirements.txt if available
if (Test-Path "requirements.txt") {
    Write-Host "Installing from requirements.txt..." -ForegroundColor Yellow
    & $pipExe install -r requirements.txt
} else {
    Write-Host "Installing packages individually..." -ForegroundColor Yellow
    & $pipExe install playwright playwright-stealth rich
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "Python dependencies installed successfully." -ForegroundColor Green
} else {
    Write-Host "ERROR: Failed to install Python packages" -ForegroundColor Red
    exit 1
}
Write-Host ""

# Install Playwright browsers
Write-Host "Installing Playwright Chromium browser..." -ForegroundColor Green
& $pythonExe -m playwright install chromium

if ($LASTEXITCODE -eq 0) {
    Write-Host "Playwright Chromium installed successfully." -ForegroundColor Green
} else {
    Write-Host "ERROR: Failed to install Playwright browsers" -ForegroundColor Red
    Write-Host "Try running: python -m playwright install chromium" -ForegroundColor Yellow
    exit 1
}
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
