@echo off
setlocal enabledelayedexpansion

:: VisionSpark ADB Setup Test Script
:: Comprehensive test of ADB installation and device connectivity

echo.
echo ========================================
echo   VisionSpark ADB Setup Test
echo ========================================
echo.

:: Test 1: Check if ADB is in PATH
echo [1/6] Testing ADB availability in PATH...
where adb >nul 2>&1
if %errorlevel%==0 (
    echo ✅ ADB found in PATH
    for /f "tokens=*" %%i in ('where adb') do (
        echo    Location: %%i
        goto :adb_found
    )
) else (
    echo ❌ ADB not found in PATH
    echo.
    echo 🔧 To fix this issue:
    echo   1. Run: npm run fix-adb-path
    echo   2. Or run: .\add-adb-to-path.bat
    echo   3. Or add manually: E:\AndroidSDK\platform-tools to PATH
    echo.
    goto :end_with_error
)

:adb_found

:: Test 2: Check ADB version
echo.
echo [2/6] Testing ADB version...
adb version >nul 2>&1
if %errorlevel%==0 (
    echo ✅ ADB is working
    for /f "tokens=*" %%i in ('adb version ^| findstr "Android Debug Bridge"') do (
        echo    %%i
    )
) else (
    echo ❌ ADB command failed
    goto :end_with_error
)

:: Test 3: Check ADB server status
echo.
echo [3/6] Testing ADB server...
adb start-server >nul 2>&1
if %errorlevel%==0 (
    echo ✅ ADB server started successfully
) else (
    echo ❌ Failed to start ADB server
    goto :end_with_error
)

:: Test 4: Check connected devices
echo.
echo [4/6] Checking connected devices...
adb devices -l > temp_devices.txt 2>&1
if %errorlevel%==0 (
    echo ✅ ADB devices command successful
    echo.
    echo 📱 Connected devices:
    type temp_devices.txt
    
    :: Count actual devices (not just the header)
    set device_count=0
    for /f "tokens=*" %%i in ('findstr /c:"device" temp_devices.txt') do (
        set /a device_count+=1
    )
    
    if !device_count! gtr 1 (
        set /a actual_devices=!device_count!-1
        echo.
        echo ✅ Found !actual_devices! connected device(s)
    ) else (
        echo.
        echo ⚠️  No devices connected
        echo.
        echo 📋 To connect a device:
        echo   1. Enable Developer Options on your Android device
        echo   2. Enable USB Debugging in Developer Options
        echo   3. Connect device via USB
        echo   4. Allow USB debugging when prompted on device
        echo   5. Run this test again
    )
    
    del temp_devices.txt >nul 2>&1
) else (
    echo ❌ Failed to check devices
    del temp_devices.txt >nul 2>&1
    goto :end_with_error
)

:: Test 5: Test device communication (if devices are connected)
echo.
echo [5/6] Testing device communication...
adb devices | findstr "device" | findstr -v "List" >nul
if %errorlevel%==0 (
    echo ✅ Testing device communication...
    adb shell echo "Device communication test successful" 2>nul
    if %errorlevel%==0 (
        echo ✅ Device communication working
        
        :: Get device info
        echo.
        echo 📋 Device Information:
        for /f "tokens=*" %%i in ('adb shell getprop ro.product.model 2^>nul') do echo    Model: %%i
        for /f "tokens=*" %%i in ('adb shell getprop ro.build.version.release 2^>nul') do echo    Android: %%i
        for /f "tokens=*" %%i in ('adb shell getprop ro.product.cpu.abi 2^>nul') do echo    Architecture: %%i
    ) else (
        echo ⚠️  Device found but communication failed
        echo    This might be normal if device authorization is pending
    )
) else (
    echo ⚠️  No devices available for communication test
)

:: Test 6: Test APK installation capability
echo.
echo [6/6] Testing APK installation capability...
if exist "build\app\outputs\flutter-apk\app-release.apk" (
    echo ✅ Release APK found: build\app\outputs\flutter-apk\app-release.apk
    
    adb devices | findstr "device" | findstr -v "List" >nul
    if %errorlevel%==0 (
        echo ✅ Ready for APK installation
        echo.
        echo 🚀 You can now run:
        echo   npm run install-apk
        echo   npm run build-and-run
    ) else (
        echo ⚠️  APK found but no devices connected for installation
    )
) else if exist "build\app\outputs\flutter-apk\app-debug.apk" (
    echo ✅ Debug APK found: build\app\outputs\flutter-apk\app-debug.apk
    echo ℹ️  No release APK found - run 'npm run build-android' first
) else (
    echo ⚠️  No APK found
    echo    Run 'npm run build-android' to create APK
)

:: Summary
echo.
echo ========================================
echo   🎉 ADB SETUP TEST COMPLETE! 🎉
echo ========================================
echo.

adb devices | findstr "device" | findstr -v "List" >nul
if %errorlevel%==0 (
    echo ✅ ADB is properly configured and devices are connected
    echo.
    echo 🚀 Ready to run VisionSpark build commands:
    echo   npm run build-and-run      - Build and install release APK
    echo   npm run build-and-run-debug - Build and install debug APK
    echo   npm run install-apk        - Install existing APK
    echo   npm run check-device       - Check device status
) else (
    echo ✅ ADB is properly configured
    echo ⚠️  Connect an Android device to complete setup
    echo.
    echo 📱 Next steps:
    echo   1. Connect Android device via USB
    echo   2. Enable USB debugging
    echo   3. Run: npm run check-device
    echo   4. Run: npm run build-and-run
)

echo.
goto :end

:end_with_error
echo.
echo ❌ ADB setup test failed
echo.
echo 🔧 Troubleshooting steps:
echo   1. Run: npm run fix-adb-path
echo   2. Or run: .\add-adb-to-path.bat
echo   3. Restart Command Prompt
echo   4. Run this test again
echo.
pause
exit /b 1

:end
pause
