#!/bin/bash
# fitgrab Linux Installation Script
# Supports: Ubuntu, Debian, Fedora, CentOS, Arch Linux, and most popular distros

set -e

echo "=========================================="
echo "  fitgrab Installation for Linux"
echo "=========================================="
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

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed."
    echo "Please install Python 3.8 or higher first."
    exit 1
fi

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
echo "Python version: $PYTHON_VERSION"
echo ""

# Install system dependencies
echo "Installing system dependencies..."

case $OS in
    ubuntu|debian|linuxmint|pop|elementary)
        echo "Detected Debian-based system"
        sudo apt-get update
        sudo apt-get install -y \
            aria2 \
            unrar \
            python3-pip \
            || { echo "ERROR: Failed to install packages"; exit 1; }
        ;;
    
    fedora|rhel|centos)
        echo "Detected Red Hat-based system"
        if command -v dnf &> /dev/null; then
            sudo dnf install -y \
                aria2 \
                unrar \
                python3-pip \
                || { echo "ERROR: Failed to install packages"; exit 1; }
        elif command -v yum &> /dev/null; then
            sudo yum install -y \
                aria2 \
                unrar \
                python3-pip \
                || { echo "ERROR: Failed to install packages"; exit 1; }
        fi
        ;;
    
    arch|manjaro)
        echo "Detected Arch-based system"
        sudo pacman -S --noconfirm \
            aria2 \
            unrar \
            python-pip \
            || { echo "ERROR: Failed to install packages"; exit 1; }
        ;;
    
    opensuse*)
        echo "Detected openSUSE"
        sudo zypper install -y \
            aria2 \
            unrar \
            python3-pip \
            || { echo "ERROR: Failed to install packages"; exit 1; }
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
    python3 -m ensurepip --upgrade || {
        echo "ERROR: Failed to install pip3"
        exit 1
    }
fi

# Install from requirements.txt
if [ -f "requirements.txt" ]; then
    pip3 install --user -r requirements.txt || {
        echo "ERROR: Failed to install Python packages"
        echo "Try: pip3 install --user playwright playwright-stealth rich"
        exit 1
    }
else
    echo "requirements.txt not found. Installing packages individually..."
    pip3 install --user playwright playwright-stealth rich || {
        echo "ERROR: Failed to install Python packages"
        exit 1
    }
fi

echo "Python dependencies installed successfully."
echo ""

# Install Playwright browsers
echo "Installing Playwright Chromium browser..."
playwright install chromium || {
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
