@echo off
setlocal enabledelayedexpansion

:: VisionSpark Flutter Build and Run Script for Windows
:: This script provides a Windows-specific implementation of the build workflow

echo.
echo ========================================
echo   VisionSpark Build and Run Script
echo ========================================
echo.

:: Check if Flutter is available
echo [1/6] Checking Flutter installation...
flutter --version >nul 2>&1
if errorlevel 1 (
    echo ❌ ERROR: Flutter is not installed or not in PATH
    echo Please install Flutter from https://flutter.dev/docs/get-started/install/windows
    pause
    exit /b 1
)
echo ✅ Flutter is available

:: Check if ADB is available
echo [2/6] Checking ADB installation...
adb version >nul 2>&1
if errorlevel 1 (
    echo ❌ ERROR: ADB is not installed or not in PATH
    echo Please install Android SDK or add platform-tools to PATH
    pause
    exit /b 1
)
echo ✅ ADB is available

:: Check for connected devices
echo [3/6] Checking connected devices...
for /f "skip=1 tokens=1" %%i in ('adb devices 2^>nul') do (
    if not "%%i"=="" (
        set DEVICE_FOUND=1
        goto :device_found
    )
)

echo ❌ ERROR: No Android devices found
echo.
echo Please ensure:
echo - USB Debugging is enabled on your Android device
echo - Device is connected via USB cable
echo - You have accepted the "Allow USB debugging" prompt
echo.
echo Current devices:
adb devices -l
pause
exit /b 1

:device_found
echo ✅ Android device detected

:: Clean and get dependencies
echo [4/6] Cleaning and getting dependencies...
flutter clean
if errorlevel 1 (
    echo ❌ ERROR: Flutter clean failed
    pause
    exit /b 1
)

flutter pub get
if errorlevel 1 (
    echo ❌ ERROR: Flutter pub get failed
    pause
    exit /b 1
)
echo ✅ Dependencies updated

:: Build APK
echo [5/6] Building release APK...
flutter build apk --release
if errorlevel 1 (
    echo ❌ ERROR: Flutter build failed
    echo.
    echo Common solutions:
    echo - Check your internet connection
    echo - Run 'flutter doctor' to check for issues
    echo - Ensure all dependencies are properly configured
    pause
    exit /b 1
)
echo ✅ APK built successfully

:: Install and launch
echo [6/6] Installing and launching app...

:: Install APK
echo Installing APK on device...
adb install -r build\app\outputs\flutter-apk\app-release.apk
if errorlevel 1 (
    echo ❌ ERROR: APK installation failed
    echo.
    echo Trying to uninstall existing version first...
    adb uninstall app.visionspark.app >nul 2>&1
    echo Retrying installation...
    adb install build\app\outputs\flutter-apk\app-release.apk
    if errorlevel 1 (
        echo ❌ ERROR: APK installation failed again
        echo Please check device storage and try manually
        pause
        exit /b 1
    )
)
echo ✅ APK installed successfully

:: Launch app
echo Launching VisionSpark...
adb shell am start -n app.visionspark.app/.MainActivity
if errorlevel 1 (
    echo ⚠️  WARNING: App launch command failed, but app may still be installed
    echo Please check your device and launch manually if needed
) else (
    echo ✅ App launched successfully
)

echo.
echo ========================================
echo   🎉 BUILD AND RUN COMPLETED! 🎉
echo ========================================
echo.
echo VisionSpark should now be running on your device.
echo APK location: build\app\outputs\flutter-apk\app-release.apk
echo.
echo To view app logs, run: adb logcat -s flutter
echo.
pause
