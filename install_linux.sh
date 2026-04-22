#!/bin/bash
# fitgrab Linux Installation Script
# Supports: Ubuntu, Debian, Fedora, CentOS, Arch Linux, and most popular distros

set -e

# ── Helper Functions ─────────────────────────────────────────────────────────────

# Retry function with exponential backoff
retry_command() {
    local max_attempts=3
    local attempt=1
    local delay=1
    
    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        fi
        echo "  Attempt $attempt/$max_attempts failed. Retrying in ${delay}s..."
        sleep $delay
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
    
    echo "  ERROR: Command failed after $max_attempts attempts: $*"
    return 1
}

# Check if command exists and works
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "  ERROR: $1 is not installed or not in PATH"
        return 1
    fi
    return 0
}

# Check Python version meets minimum requirement
check_python_version() {
    local min_major=3
    local min_minor=8
    local version_str=$(python3 --version 2>&1 | awk '{print $2}')
    local major=$(echo $version_str | cut -d'.' -f1)
    local minor=$(echo $version_str | cut -d'.' -f2)
    
    if [ "$major" -lt "$min_major" ] || ([ "$major" -eq "$min_major" ] && [ "$minor" -lt "$min_minor" ]); then
        echo "  ERROR: Python $version_str is too old. Need Python $min_major.$min_minor or higher."
        return 1
    fi
    return 0
}

# Check available disk space (in MB)
check_disk_space() {
    local required_mb=500
    local available_mb=$(df -m "$HOME" | tail -1 | awk '{print $4}')
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        echo "  ERROR: Insufficient disk space. Need ${required_mb}MB, have ${available_mb}MB available."
        return 1
    fi
    return 0
}

# Check if running with sudo privileges
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        echo "  ERROR: This script requires sudo privileges."
        echo "  Please re-run with: sudo $0"
        return 1
    fi
    return 0
}

# Check network connectivity
check_network() {
    if ! ping -c 1 -W 2 github.com &> /dev/null; then
        echo "  ERROR: Cannot reach GitHub. Please check your internet connection."
        return 1
    fi
    return 0
}

# ── Pre-flight Checks ───────────────────────────────────────────────────────────

echo "=========================================="
echo "  fitgrab Installation for Linux"
echo "=========================================="
echo ""
echo "Running pre-flight checks..."
echo ""

# Check network
if ! check_network; then
    exit 1
fi

# Check Python version
if ! check_python_version; then
    exit 1
fi

# Check disk space
if ! check_disk_space; then
    exit 1
fi

# Check sudo (only if needed for package installation)
# We'll check this later when we actually need it

echo "Pre-flight checks passed."
echo ""

# Detect OS family
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
else
    echo "ERROR: Cannot detect OS. Please install manually."
    exit 1
fi

echo "Detected OS: $OS $OS_VERSION"
echo ""

# Install system dependencies
echo "Installing system dependencies..."

# Check sudo before attempting package installation
if ! check_sudo; then
    exit 1
fi

case $OS in
    ubuntu|debian|linuxmint|pop|elementary)
        echo "Detected Debian-based system"
        retry_command sudo apt-get update || { echo "ERROR: Failed to update package lists"; exit 1; }
        retry_command sudo apt-get install -y aria2 unrar python3-pip || { echo "ERROR: Failed to install packages"; exit 1; }
        ;;

    fedora|rhel|centos)
        echo "Detected Red Hat-based system"
        if command -v dnf &> /dev/null; then
            retry_command sudo dnf install -y aria2 unrar python3-pip || { echo "ERROR: Failed to install packages"; exit 1; }
        elif command -v yum &> /dev/null; then
            retry_command sudo yum install -y aria2 unrar python3-pip || { echo "ERROR: Failed to install packages"; exit 1; }
        else
            echo "ERROR: Neither dnf nor yum found. Cannot install packages."
            exit 1
        fi
        ;;

    arch|manjaro)
        echo "Detected Arch-based system"
        retry_command sudo pacman -S --noconfirm aria2 unrar python-pip || { echo "ERROR: Failed to install packages"; exit 1; }
        ;;

    opensuse*)
        echo "Detected openSUSE"
        retry_command sudo zypper install -y aria2 unrar python3-pip || { echo "ERROR: Failed to install packages"; exit 1; }
        ;;

    *)
        echo "WARNING: Unknown OS '$OS'. Attempting generic installation..."
        echo "Please ensure aria2 and unrar are installed manually."
        ;;
esac

echo "System dependencies installed successfully."
echo ""

# Install Python dependencies
echo "Installing Python dependencies..."

# Check if pip is available
if ! command -v pip3 &> /dev/null; then
    echo "pip3 not found. Installing..."
    retry_command python3 -m ensurepip --upgrade || {
        echo "ERROR: Failed to install pip3"
        exit 1
    }
fi

# Install from requirements.txt
if [ -f "requirements.txt" ]; then
    retry_command pip3 install --user -r requirements.txt || {
        echo "ERROR: Failed to install Python packages"
        echo "Try: pip3 install --user playwright playwright-stealth rich"
        exit 1
    }
else
    echo "requirements.txt not found. Installing packages individually..."
    retry_command pip3 install --user playwright playwright-stealth rich || {
        echo "ERROR: Failed to install Python packages"
        exit 1
    }
fi

echo "Python dependencies installed successfully."
echo ""

# Install Playwright browsers
echo "Installing Playwright Chromium browser..."
retry_command playwright install chromium || {
    echo "ERROR: Failed to install Playwright browsers"
    echo "Try: playwright install chromium"
    exit 1
}

echo "Playwright Chromium installed successfully."
echo ""

# Move fitgrab to ~/.local/bin/
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

if [ -f "fitgrab" ]; then
    cp fitgrab "$LOCAL_BIN/fitgrab"
    chmod u+x "$LOCAL_BIN/fitgrab"
    echo "Installed fitgrab to $LOCAL_BIN/fitgrab"
    echo ""
else
    echo "WARNING: fitgrab file not found in current directory"
fi

# ── Post-installation Validation ──────────────────────────────────────────────

echo "Validating installation..."
echo ""

# Validate aria2c
if check_command aria2c; then
    echo "  ✓ aria2c installed and working"
else
    echo "  ✗ aria2c validation failed"
    exit 1
fi

# Validate unrar (optional)
if check_command unrar; then
    echo "  ✓ unrar installed and working"
else
    echo "  ⚠ unrar not found (optional for archive testing)"
fi

# Validate Python packages
if python3 -c "import playwright" 2>/dev/null; then
    echo "  ✓ playwright installed"
else
    echo "  ✗ playwright validation failed"
    exit 1
fi

if python3 -c "import rich" 2>/dev/null; then
    echo "  ✓ rich installed"
else
    echo "  ⚠ rich not found (optional for beautiful TUI)"
fi

# Validate fitgrab
if [ -f "$LOCAL_BIN/fitgrab" ]; then
    if "$LOCAL_BIN/fitgrab" --help &> /dev/null; then
        echo "  ✓ fitgrab installed and working"
    else
        echo "  ✗ fitgrab validation failed"
        exit 1
    fi
else
    echo "  ⚠ fitgrab not found in $LOCAL_BIN"
fi

echo ""
echo "All validations passed."
echo ""

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "To run fitgrab:"
echo "  fitgrab <fitgirl-url> --dir ~/Games"
echo ""
echo "Example:"
echo "  fitgrab https://fitgirl-repacks.site/god-of-war-ragnarok/ --dir ~/Games"
echo ""
echo "For more info: fitgrab --help"
echo ""
