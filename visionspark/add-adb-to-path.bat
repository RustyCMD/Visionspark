@echo off
setlocal enabledelayedexpansion

:: VisionSpark ADB PATH Setup Script
:: Adds Android SDK platform-tools to Windows PATH

echo.
echo ========================================
echo   Adding ADB to Windows PATH
echo ========================================
echo.

:: Check if running as administrator
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Running as Administrator - will modify system PATH
    set "SCOPE=MACHINE"
    set "REGKEY=HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
) else (
    echo Running as User - will modify user PATH
    set "SCOPE=USER"
    set "REGKEY=HKEY_CURRENT_USER\Environment"
)

:: Detect Android SDK location
set "ADB_PATH="
set "SDK_FOUND=0"

echo [1/4] Detecting Android SDK location...

:: Check your specific location first
if exist "E:\AndroidSDK\platform-tools\adb.exe" (
    set "ADB_PATH=E:\AndroidSDK\platform-tools"
    set "SDK_FOUND=1"
    echo ✅ Found Android SDK at: E:\AndroidSDK
    goto :path_found
)

:: Check other common locations
set "COMMON_PATHS=C:\Android\Sdk %LOCALAPPDATA%\Android\Sdk %USERPROFILE%\AppData\Local\Android\Sdk C:\Users\%USERNAME%\AppData\Local\Android\Sdk"

for %%p in (%COMMON_PATHS%) do (
    if exist "%%p\platform-tools\adb.exe" (
        set "ADB_PATH=%%p\platform-tools"
        set "SDK_FOUND=1"
        echo ✅ Found Android SDK at: %%p
        goto :path_found
    )
)

:path_found
if %SDK_FOUND%==0 (
    echo ❌ Android SDK not found in common locations
    echo.
    echo Please ensure Android SDK is installed and try again.
    echo Expected locations:
    echo   - E:\AndroidSDK\platform-tools\adb.exe
    echo   - %LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
    pause
    exit /b 1
)

echo    ADB location: %ADB_PATH%\adb.exe

:: Check if ADB is already in PATH
echo [2/4] Checking current PATH...
echo %PATH% | findstr /i "%ADB_PATH%" >nul
if %errorlevel%==0 (
    echo ✅ ADB path is already in PATH
    goto :test_adb
) else (
    echo ⚠️  ADB path not found in current PATH
)

:: Get current PATH value
echo [3/4] Adding ADB to PATH...
for /f "tokens=2*" %%a in ('reg query "%REGKEY%" /v PATH 2^>nul') do set "CURRENT_PATH=%%b"

:: Add ADB path to PATH if not already present
echo %CURRENT_PATH% | findstr /i "%ADB_PATH%" >nul
if %errorlevel%==0 (
    echo ✅ ADB path already exists in registry PATH
) else (
    echo Adding %ADB_PATH% to PATH...
    if defined CURRENT_PATH (
        set "NEW_PATH=%CURRENT_PATH%;%ADB_PATH%"
    ) else (
        set "NEW_PATH=%ADB_PATH%"
    )
    
    reg add "%REGKEY%" /v PATH /t REG_EXPAND_SZ /d "!NEW_PATH!" /f >nul
    if %errorlevel%==0 (
        echo ✅ Successfully added ADB to PATH
    ) else (
        echo ❌ Failed to add ADB to PATH
        echo Try running as Administrator for system-wide PATH
        pause
        exit /b 1
    )
)

:: Update current session PATH
set "PATH=%PATH%;%ADB_PATH%"

:test_adb
echo [4/4] Testing ADB installation...
adb version >nul 2>&1
if %errorlevel%==0 (
    echo ✅ ADB is working!
    echo.
    echo ADB Version:
    adb version | findstr "Android Debug Bridge"
    echo.
    echo Testing device connection...
    adb devices
    echo.
    echo ========================================
    echo   🎉 ADB SETUP COMPLETE! 🎉
    echo ========================================
    echo.
    echo You can now run:
    echo   npm run check-device
    echo   npm run install-apk
    echo   npm run build-and-run
    echo.
    echo Note: You may need to restart Command Prompt
    echo for the PATH changes to take effect in new sessions.
) else (
    echo ❌ ADB test failed
    echo PATH may not be updated in current session
    echo Please restart Command Prompt and try: adb version
)

echo.
pause
