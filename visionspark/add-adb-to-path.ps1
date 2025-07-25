# VisionSpark ADB PATH Setup Script (PowerShell)
# Adds Android SDK platform-tools to Windows PATH

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   Adding ADB to Windows PATH" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if ($isAdmin) {
    Write-Host "Running as Administrator - will modify system PATH" -ForegroundColor Green
    $scope = "Machine"
} else {
    Write-Host "Running as User - will modify user PATH" -ForegroundColor Yellow
    $scope = "User"
}

# Detect Android SDK location
Write-Host "[1/4] Detecting Android SDK location..." -ForegroundColor Blue

$adbPath = $null
$sdkFound = $false

# Check your specific location first
if (Test-Path "E:\AndroidSDK\platform-tools\adb.exe") {
    $adbPath = "E:\AndroidSDK\platform-tools"
    $sdkFound = $true
    Write-Host "✅ Found Android SDK at: E:\AndroidSDK" -ForegroundColor Green
}

# Check other common locations if not found
if (-not $sdkFound) {
    $commonPaths = @(
        "C:\Android\Sdk",
        "$env:LOCALAPPDATA\Android\Sdk",
        "$env:USERPROFILE\AppData\Local\Android\Sdk"
    )
    
    foreach ($path in $commonPaths) {
        $testPath = Join-Path $path "platform-tools\adb.exe"
        if (Test-Path $testPath) {
            $adbPath = Join-Path $path "platform-tools"
            $sdkFound = $true
            Write-Host "✅ Found Android SDK at: $path" -ForegroundColor Green
            break
        }
    }
}

if (-not $sdkFound) {
    Write-Host "❌ Android SDK not found in common locations" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please ensure Android SDK is installed and try again."
    Write-Host "Expected locations:"
    Write-Host "  - E:\AndroidSDK\platform-tools\adb.exe"
    Write-Host "  - $env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "   ADB location: $adbPath\adb.exe" -ForegroundColor White

# Check if ADB is already in PATH
Write-Host "[2/4] Checking current PATH..." -ForegroundColor Blue
$currentPath = [Environment]::GetEnvironmentVariable("PATH", $scope)
if ($currentPath -like "*$adbPath*") {
    Write-Host "✅ ADB path is already in PATH" -ForegroundColor Green
} else {
    Write-Host "⚠️  ADB path not found in current PATH" -ForegroundColor Yellow
    
    # Add ADB path to PATH
    Write-Host "[3/4] Adding ADB to PATH..." -ForegroundColor Blue
    try {
        $newPath = if ($currentPath) { "$currentPath;$adbPath" } else { $adbPath }
        [Environment]::SetEnvironmentVariable("PATH", $newPath, $scope)
        Write-Host "✅ Successfully added ADB to PATH" -ForegroundColor Green
        
        # Update current session PATH
        $env:PATH += ";$adbPath"
    }
    catch {
        Write-Host "❌ Failed to add ADB to PATH: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Try running PowerShell as Administrator" -ForegroundColor Yellow
        Read-Host "Press Enter to exit"
        exit 1
    }
}

# Test ADB installation
Write-Host "[4/4] Testing ADB installation..." -ForegroundColor Blue
try {
    $adbVersion = & adb version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ ADB is working!" -ForegroundColor Green
        Write-Host ""
        Write-Host "ADB Version:" -ForegroundColor White
        Write-Host ($adbVersion | Select-String "Android Debug Bridge").Line -ForegroundColor Gray
        Write-Host ""
        Write-Host "Testing device connection..." -ForegroundColor Blue
        & adb devices
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "   🎉 ADB SETUP COMPLETE! 🎉" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "You can now run:" -ForegroundColor White
        Write-Host "  npm run check-device" -ForegroundColor Green
        Write-Host "  npm run install-apk" -ForegroundColor Green
        Write-Host "  npm run build-and-run" -ForegroundColor Green
        Write-Host ""
        Write-Host "Note: You may need to restart Command Prompt" -ForegroundColor Yellow
        Write-Host "for the PATH changes to take effect in new sessions." -ForegroundColor Yellow
    } else {
        throw "ADB command failed"
    }
}
catch {
    Write-Host "❌ ADB test failed" -ForegroundColor Red
    Write-Host "PATH may not be updated in current session" -ForegroundColor Yellow
    Write-Host "Please restart Command Prompt and try: adb version" -ForegroundColor White
}

Write-Host ""
Read-Host "Press Enter to continue"
