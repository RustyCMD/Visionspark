@echo off
setlocal enabledelayedexpansion

:: VisionSpark Setup Test Script for Windows
:: Quick test to verify Flutter and ADB are working

echo.
echo ========================================
echo   VisionSpark Setup Test
echo ========================================
echo.

:: Test Node.js
echo [1/5] Testing Node.js...
node --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Node.js not found
    echo Please install Node.js from https://nodejs.org/
    goto :error
) else (
    for /f "tokens=*" %%i in ('node --version') do echo ✅ Node.js: %%i
)

:: Test npm
echo [2/5] Testing npm...
npm --version >nul 2>&1
if errorlevel 1 (
    echo ❌ npm not found
    goto :error
) else (
    for /f "tokens=*" %%i in ('npm --version') do echo ✅ npm: %%i
)

:: Test Flutter
echo [3/5] Testing Flutter...
flutter --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Flutter not found in PATH
    echo.
    echo 🔧 To fix this issue:
    echo 1. Run: npm run fix-flutter-path
    echo 2. Or manually add Flutter to your Windows PATH
    echo 3. Restart Command Prompt and try again
    goto :error
) else (
    echo ✅ Flutter is available
    for /f "tokens=1,2,3" %%a in ('flutter --version ^| findstr "Flutter"') do (
        echo    Version: %%a %%b %%c
    )
)

:: Test ADB
echo [4/5] Testing ADB...
adb version >nul 2>&1
if errorlevel 1 (
    echo ❌ ADB not found in PATH
    echo.
    echo 🔧 To fix this issue:
    echo 1. Install Android Studio
    echo 2. Add Android SDK platform-tools to PATH
    echo 3. Or run: npm run setup for detailed instructions
    goto :error
) else (
    echo ✅ ADB is available
    for /f "tokens=*" %%i in ('adb version ^| findstr "Android Debug Bridge"') do echo    %%i
)

:: Test connected devices
echo [5/5] Testing connected devices...
for /f "skip=1 tokens=1" %%i in ('adb devices 2^>nul') do (
    if not "%%i"=="" (
        set DEVICE_FOUND=1
        goto :device_found
    )
)

echo ⚠️  No Android devices connected
echo.
echo 📱 To connect a device:
echo 1. Enable USB Debugging on your Android device
echo 2. Connect via USB cable
echo 3. Accept "Allow USB debugging" prompt
echo 4. Run: adb devices
goto :no_device

:device_found
echo ✅ Android device(s) connected
adb devices -l

:no_device
echo.
echo ========================================
echo   SETUP TEST COMPLETE
echo ========================================
echo.

:: Check if all essential tools are available
flutter --version >nul 2>&1
set FLUTTER_OK=!errorlevel!
adb version >nul 2>&1
set ADB_OK=!errorlevel!

if !FLUTTER_OK! equ 0 if !ADB_OK! equ 0 (
    echo 🎉 All essential tools are working!
    echo.
    echo You can now run:
    echo   npm run build-and-run
    echo.
    if defined DEVICE_FOUND (
        echo Your device is ready for app installation.
    ) else (
        echo Connect your Android device to complete the setup.
    )
) else (
    echo ⚠️  Some tools need to be fixed.
    echo.
    echo Next steps:
    if !FLUTTER_OK! neq 0 echo   npm run fix-flutter-path
    if !ADB_OK! neq 0 echo   Install Android Studio and add ADB to PATH
    echo   npm run setup  ^(comprehensive check^)
)

echo.
echo For detailed help: npm run help
echo.
pause
exit /b 0

:error
echo.
echo ❌ Setup test failed. Please fix the issues above.
echo.
echo For help:
echo   npm run setup         - Comprehensive setup check
echo   npm run fix-flutter-path - Fix Flutter PATH issues
echo   npm run help          - Show all available commands
echo.
pause
exit /b 1
