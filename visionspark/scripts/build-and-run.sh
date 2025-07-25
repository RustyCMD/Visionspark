#!/bin/bash

# VisionSpark Flutter Build and Run Script for macOS/Linux
# This script provides a Unix-specific implementation of the build workflow

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo ""
echo "========================================"
echo "   VisionSpark Build and Run Script"
echo "========================================"
echo ""

# Check if Flutter is available
print_status "[1/6] Checking Flutter installation..."
if ! command -v flutter &> /dev/null; then
    print_error "Flutter is not installed or not in PATH"
    echo "Please install Flutter from https://flutter.dev/docs/get-started/install"
    exit 1
fi
print_success "Flutter is available"

# Check if ADB is available
print_status "[2/6] Checking ADB installation..."
if ! command -v adb &> /dev/null; then
    print_error "ADB is not installed or not in PATH"
    echo "Please install Android SDK or add platform-tools to PATH"
    exit 1
fi
print_success "ADB is available"

# Check for connected devices
print_status "[3/6] Checking connected devices..."
DEVICE_COUNT=$(adb devices | grep -c "device$" || true)
if [ "$DEVICE_COUNT" -eq 0 ]; then
    print_error "No Android devices found"
    echo ""
    echo "Please ensure:"
    echo "- USB Debugging is enabled on your Android device"
    echo "- Device is connected via USB cable"
    echo "- You have accepted the 'Allow USB debugging' prompt"
    echo ""
    echo "Current devices:"
    adb devices -l
    exit 1
fi
print_success "Android device detected ($DEVICE_COUNT device(s))"

# Show device info
print_status "Connected device info:"
adb shell getprop ro.product.model 2>/dev/null || echo "Model: Unknown"
adb shell getprop ro.build.version.release 2>/dev/null || echo "Android version: Unknown"

# Clean and get dependencies
print_status "[4/6] Cleaning and getting dependencies..."
flutter clean
if [ $? -ne 0 ]; then
    print_error "Flutter clean failed"
    exit 1
fi

flutter pub get
if [ $? -ne 0 ]; then
    print_error "Flutter pub get failed"
    exit 1
fi
print_success "Dependencies updated"

# Build APK
print_status "[5/6] Building release APK..."
flutter build apk --release
if [ $? -ne 0 ]; then
    print_error "Flutter build failed"
    echo ""
    echo "Common solutions:"
    echo "- Check your internet connection"
    echo "- Run 'flutter doctor' to check for issues"
    echo "- Ensure all dependencies are properly configured"
    exit 1
fi
print_success "APK built successfully"

# Install and launch
print_status "[6/6] Installing and launching app..."

# Install APK
print_status "Installing APK on device..."
if ! adb install -r build/app/outputs/flutter-apk/app-release.apk; then
    print_warning "Installation failed, trying to uninstall existing version first..."
    adb uninstall app.visionspark.app &> /dev/null || true
    print_status "Retrying installation..."
    if ! adb install build/app/outputs/flutter-apk/app-release.apk; then
        print_error "APK installation failed"
        echo "Please check device storage and try manually"
        exit 1
    fi
fi
print_success "APK installed successfully"

# Launch app
print_status "Launching VisionSpark..."
if ! adb shell am start -n app.visionspark.app/.MainActivity; then
    print_warning "App launch command failed, but app may still be installed"
    echo "Please check your device and launch manually if needed"
else
    print_success "App launched successfully"
fi

echo ""
echo "========================================"
echo "   🎉 BUILD AND RUN COMPLETED! 🎉"
echo "========================================"
echo ""
echo "VisionSpark should now be running on your device."
echo "APK location: build/app/outputs/flutter-apk/app-release.apk"
echo ""
echo "To view app logs, run: adb logcat -s flutter"
echo ""

# Optional: Show logs for a few seconds
read -p "Would you like to view app logs now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Showing app logs (press Ctrl+C to stop)..."
    adb logcat -s flutter
fi
