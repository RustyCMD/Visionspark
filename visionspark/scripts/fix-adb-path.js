#!/usr/bin/env node

/**
 * VisionSpark ADB PATH Fix Script
 * Automatically adds Android SDK platform-tools to Windows PATH
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Colors for console output
const colors = {
    reset: '\x1b[0m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m'
};

function colorLog(color, message) {
    console.log(`${colors[color]}${message}${colors.reset}`);
}

function findAndroidSdkPath() {
    const commonPaths = [
        // User's specific Android SDK location (detected from screenshots)
        'E:\\AndroidSDK',
        // Standard locations
        path.join(os.homedir(), 'AppData', 'Local', 'Android', 'Sdk'),
        'C:\\Android\\Sdk',
        'C:\\Users\\Public\\Android\\Sdk',
        path.join(os.homedir(), 'Android', 'Sdk'),
        // Additional common locations
        'D:\\AndroidSDK',
        'C:\\AndroidSDK',
        path.join(os.homedir(), 'AndroidSDK')
    ];

    for (const sdkPath of commonPaths) {
        const adbPath = path.join(sdkPath, 'platform-tools', 'adb.exe');
        if (fs.existsSync(adbPath)) {
            return { path: sdkPath, adbPath, platformToolsPath: path.join(sdkPath, 'platform-tools') };
        }
    }

    return null;
}

function isAdbInPath() {
    try {
        execSync('where adb', { 
            encoding: 'utf8', 
            stdio: 'pipe',
            windowsHide: true 
        });
        return true;
    } catch (error) {
        return false;
    }
}

function addToUserPath(newPath) {
    try {
        // Get current user PATH
        const getCurrentPath = 'reg query "HKEY_CURRENT_USER\\Environment" /v PATH';
        let currentPath = '';
        
        try {
            const output = execSync(getCurrentPath, { encoding: 'utf8', windowsHide: true });
            const match = output.match(/PATH\s+REG_[A-Z_]+\s+(.+)/);
            if (match) {
                currentPath = match[1].trim();
            }
        } catch (error) {
            // PATH might not exist in user environment
            colorLog('yellow', '   No existing user PATH found, creating new one');
        }

        // Check if path already exists
        if (currentPath.toLowerCase().includes(newPath.toLowerCase())) {
            colorLog('green', '✅ ADB path already exists in user PATH');
            return true;
        }

        // Add new path
        const updatedPath = currentPath ? `${currentPath};${newPath}` : newPath;
        const setPathCommand = `reg add "HKEY_CURRENT_USER\\Environment" /v PATH /t REG_EXPAND_SZ /d "${updatedPath}" /f`;
        
        execSync(setPathCommand, { windowsHide: true });
        colorLog('green', '✅ Successfully added ADB to user PATH');
        
        // Update current session PATH
        process.env.PATH += `;${newPath}`;
        
        return true;
    } catch (error) {
        colorLog('red', `❌ Failed to add ADB to PATH: ${error.message}`);
        return false;
    }
}

function testAdbInstallation() {
    try {
        const output = execSync('adb version', { 
            encoding: 'utf8', 
            stdio: 'pipe',
            windowsHide: true 
        });
        
        colorLog('green', '✅ ADB is working!');
        console.log('   ' + output.split('\n')[0]);
        
        // Test device connection
        try {
            const devices = execSync('adb devices', { 
                encoding: 'utf8', 
                stdio: 'pipe',
                windowsHide: true 
            });
            console.log('\n📱 Connected devices:');
            console.log(devices);
        } catch (deviceError) {
            colorLog('yellow', '⚠️  Could not check devices (this is normal if no devices are connected)');
        }
        
        return true;
    } catch (error) {
        colorLog('red', '❌ ADB test failed');
        colorLog('yellow', '   You may need to restart Command Prompt for PATH changes to take effect');
        return false;
    }
}

async function main() {
    console.log('\n' + '='.repeat(50));
    colorLog('cyan', '   VisionSpark ADB PATH Fix');
    console.log('='.repeat(50));

    // Check if ADB is already available
    colorLog('blue', '\n[1/4] Checking current ADB availability...');
    if (isAdbInPath()) {
        colorLog('green', '✅ ADB is already available in PATH');
        testAdbInstallation();
        console.log('\n🎉 No fix needed! ADB is working correctly.');
        return;
    }

    colorLog('yellow', '⚠️  ADB not found in PATH');

    // Find Android SDK
    colorLog('blue', '\n[2/4] Searching for Android SDK...');
    const androidSdk = findAndroidSdkPath();
    
    if (!androidSdk) {
        colorLog('red', '❌ Android SDK not found in common locations');
        console.log('\n📥 Please install Android SDK first:');
        console.log('   1. Download Android Studio from: https://developer.android.com/studio');
        console.log('   2. Install and run Android Studio');
        console.log('   3. Go to Tools > SDK Manager');
        console.log('   4. Install Android SDK Platform-Tools');
        console.log('   5. Run this script again');
        return;
    }

    colorLog('green', `✅ Found Android SDK: ${androidSdk.path}`);
    console.log(`   ADB location: ${androidSdk.adbPath}`);

    // Add to PATH
    colorLog('blue', '\n[3/4] Adding ADB to Windows PATH...');
    const success = addToUserPath(androidSdk.platformToolsPath);
    
    if (!success) {
        console.log('\n❌ Automated fix failed. Please add manually:');
        console.log('   1. Press Win + R, type "sysdm.cpl" and press Enter');
        console.log('   2. Click "Environment Variables" button');
        console.log('   3. Under "User variables", find "Path" and click "Edit"');
        console.log('   4. Click "New" and add:');
        colorLog('green', `      ${androidSdk.platformToolsPath}`);
        console.log('   5. Click "OK" on all dialogs');
        console.log('   6. Restart Command Prompt');
        return;
    }

    // Test installation
    colorLog('blue', '\n[4/4] Testing ADB installation...');
    const testSuccess = testAdbInstallation();

    // Summary
    console.log('\n' + '='.repeat(50));
    if (testSuccess) {
        colorLog('green', '🎉 ADB PATH FIX COMPLETE!');
        console.log('\nYou can now run:');
        colorLog('green', '   npm run check-device');
        colorLog('green', '   npm run install-apk');
        colorLog('green', '   npm run build-and-run');
        console.log('\nNote: If ADB still doesn\'t work in new Command Prompt windows,');
        console.log('restart your computer to ensure PATH changes take effect.');
    } else {
        colorLog('yellow', '⚠️  PATH updated but ADB test failed');
        console.log('\nPlease restart Command Prompt and try:');
        colorLog('green', '   adb version');
        console.log('\nIf it still doesn\'t work, restart your computer.');
    }
    
    console.log('\n');
}

// Run the fix
main().catch(error => {
    colorLog('red', `Error during ADB PATH fix: ${error.message}`);
    process.exit(1);
});
