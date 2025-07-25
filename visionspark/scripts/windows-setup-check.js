#!/usr/bin/env node

/**
 * VisionSpark Windows Setup Verification Script
 * Comprehensive check for Flutter Android development on Windows
 */

const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

// Colors for console output (Windows compatible)
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

function checkWindowsCommand(command, name, installUrl = '') {
    try {
        const output = execSync(command, { 
            encoding: 'utf8', 
            stdio: 'pipe',
            windowsHide: true 
        });
        colorLog('green', `✅ ${name} is available`);
        return { available: true, output: output.trim() };
    } catch (error) {
        colorLog('red', `❌ ${name} is not available`);
        if (installUrl) {
            colorLog('yellow', `   Install from: ${installUrl}`);
        }
        return { available: false, error: error.message };
    }
}

function checkFlutterInPath() {
    try {
        const output = execSync('where flutter', { 
            encoding: 'utf8', 
            stdio: 'pipe',
            windowsHide: true 
        });
        const flutterPath = output.trim().split('\n')[0];
        colorLog('green', `✅ Flutter found in PATH: ${flutterPath}`);
        return { available: true, path: flutterPath };
    } catch (error) {
        colorLog('red', '❌ Flutter not found in PATH');
        return { available: false };
    }
}

function checkAdbInPath() {
    try {
        const output = execSync('where adb', { 
            encoding: 'utf8', 
            stdio: 'pipe',
            windowsHide: true 
        });
        const adbPath = output.trim().split('\n')[0];
        colorLog('green', `✅ ADB found in PATH: ${adbPath}`);
        return { available: true, path: adbPath };
    } catch (error) {
        colorLog('red', '❌ ADB not found in PATH');
        return { available: false };
    }
}

function findFlutterInstallations() {
    const commonPaths = [
        'C:\\flutter',
        'C:\\src\\flutter',
        'C:\\tools\\flutter',
        path.join(os.homedir(), 'flutter'),
        path.join(os.homedir(), 'AppData', 'Local', 'flutter'),
        path.join(os.homedir(), 'Documents', 'flutter')
    ];

    const found = [];
    for (const flutterPath of commonPaths) {
        const flutterExe = path.join(flutterPath, 'bin', 'flutter.bat');
        if (fs.existsSync(flutterExe)) {
            found.push(flutterPath);
        }
    }

    return found;
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
            return { path: sdkPath, adbPath };
        }
    }

    return null;
}

async function checkDevices() {
    try {
        const output = execSync('adb devices -l', { 
            encoding: 'utf8', 
            stdio: 'pipe',
            windowsHide: true 
        });
        const lines = output.split('\n').filter(line => line.includes('\tdevice'));
        
        if (lines.length > 0) {
            colorLog('green', `✅ ${lines.length} Android device(s) connected`);
            lines.forEach((line, index) => {
                const parts = line.split('\t');
                const deviceId = parts[0];
                const info = parts.slice(2).join(' ');
                console.log(`   Device ${index + 1}: ${deviceId} ${info}`);
            });
            return true;
        } else {
            colorLog('yellow', '⚠️  No Android devices connected');
            colorLog('blue', '   Connect your device and enable USB debugging');
            return false;
        }
    } catch (error) {
        colorLog('red', '❌ Failed to check devices (ADB not available)');
        return false;
    }
}

function generatePathFixInstructions(flutterInstalls, androidSdk) {
    console.log('\n' + '='.repeat(60));
    colorLog('cyan', '   PATH FIX INSTRUCTIONS');
    console.log('='.repeat(60));

    if (flutterInstalls.length > 0) {
        colorLog('yellow', '\n📍 Flutter installations found:');
        flutterInstalls.forEach((install, index) => {
            console.log(`   ${index + 1}. ${install}`);
        });

        console.log('\n🔧 To add Flutter to PATH:');
        console.log('   1. Press Win + R, type "sysdm.cpl" and press Enter');
        console.log('   2. Click "Environment Variables" button');
        console.log('   3. Under "User variables", find and select "Path", then click "Edit"');
        console.log('   4. Click "New" and add this path:');
        colorLog('green', `      ${path.join(flutterInstalls[0], 'bin')}`);
        console.log('   5. Click "OK" on all dialogs');
        console.log('   6. Restart Command Prompt/PowerShell');
        console.log('   7. Test with: flutter --version');
    } else {
        colorLog('red', '\n❌ No Flutter installations found in common locations');
        console.log('\n📥 To install Flutter:');
        console.log('   1. Download Flutter SDK from: https://flutter.dev/docs/get-started/install/windows');
        console.log('   2. Extract to C:\\flutter');
        console.log('   3. Add C:\\flutter\\bin to your PATH (see instructions above)');
    }

    if (androidSdk) {
        console.log('\n🔧 To add ADB to PATH:');
        console.log('   Follow the same PATH steps above, but add:');
        colorLog('green', `      ${path.join(androidSdk.path, 'platform-tools')}`);
        console.log('\n💡 Quick ADB PATH fix options:');
        colorLog('cyan', '   Option 1: Run our automated batch script:');
        colorLog('green', '     .\\add-adb-to-path.bat');
        colorLog('cyan', '   Option 2: Run our PowerShell script (as Admin):');
        colorLog('green', '     PowerShell -ExecutionPolicy Bypass -File .\\add-adb-to-path.ps1');
        colorLog('cyan', '   Option 3: Add manually using the steps above');
    } else {
        colorLog('red', '\n❌ Android SDK not found');
        console.log('\n📥 To install Android SDK:');
        console.log('   1. Download Android Studio from: https://developer.android.com/studio');
        console.log('   2. Install and run Android Studio');
        console.log('   3. Go to Tools > SDK Manager');
        console.log('   4. Install Android SDK Platform-Tools');
        console.log('   5. Add platform-tools to PATH');
    }

    console.log('\n💡 Alternative automated fixes:');
    colorLog('green', '   npm run fix-flutter-path  # Fix Flutter PATH');
    colorLog('green', '   npm run fix-adb-path      # Fix ADB PATH (coming soon)');
}

async function main() {
    console.log('\n' + '='.repeat(50));
    colorLog('cyan', '   VisionSpark Windows Setup Check');
    console.log('='.repeat(50));

    let allGood = true;
    const results = {};

    // Check Windows version
    colorLog('blue', '\n1. Checking Windows environment...');
    console.log(`   OS: ${os.type()} ${os.release()}`);
    console.log(`   Architecture: ${os.arch()}`);

    // Check Node.js
    colorLog('blue', '\n2. Checking Node.js...');
    results.node = checkWindowsCommand('node --version', 'Node.js', 'https://nodejs.org/');

    // Check npm
    colorLog('blue', '\n3. Checking npm...');
    results.npm = checkWindowsCommand('npm --version', 'npm');

    // Check Flutter in PATH
    colorLog('blue', '\n4. Checking Flutter in PATH...');
    results.flutterPath = checkFlutterInPath();

    // Check ADB in PATH
    colorLog('blue', '\n5. Checking ADB in PATH...');
    results.adbPath = checkAdbInPath();

    if (!results.adbPath.available) {
        colorLog('yellow', '   💡 This is likely your issue! ADB not found in PATH.');
    }

    // Find Flutter installations
    colorLog('blue', '\n6. Searching for Flutter installations...');
    const flutterInstalls = findFlutterInstallations();
    if (flutterInstalls.length > 0) {
        colorLog('green', `✅ Found ${flutterInstalls.length} Flutter installation(s)`);
        flutterInstalls.forEach(install => console.log(`   - ${install}`));
    } else {
        colorLog('red', '❌ No Flutter installations found');
        allGood = false;
    }

    // Find Android SDK
    colorLog('blue', '\n7. Searching for Android SDK...');
    const androidSdk = findAndroidSdkPath();
    if (androidSdk) {
        colorLog('green', `✅ Android SDK found: ${androidSdk.path}`);
        console.log(`   ADB location: ${androidSdk.adbPath}`);
    } else {
        colorLog('red', '❌ Android SDK not found');
        allGood = false;
    }

    // Check connected devices (if ADB is available)
    if (results.adbPath.available) {
        colorLog('blue', '\n8. Checking connected devices...');
        results.devices = await checkDevices();
    }

    // Test Flutter if available
    if (results.flutterPath.available) {
        colorLog('blue', '\n9. Testing Flutter...');
        try {
            const flutterVersion = execSync('flutter --version', { 
                encoding: 'utf8', 
                stdio: 'pipe',
                windowsHide: true 
            });
            colorLog('green', '✅ Flutter is working');
            console.log('   ' + flutterVersion.split('\n')[0]);
        } catch (error) {
            colorLog('red', '❌ Flutter command failed');
            allGood = false;
        }
    }

    // Summary
    console.log('\n' + '='.repeat(50));
    colorLog('cyan', '   SETUP VERIFICATION SUMMARY');
    console.log('='.repeat(50));

    const checks = [
        { name: 'Node.js', status: results.node?.available },
        { name: 'npm', status: results.npm?.available },
        { name: 'Flutter in PATH', status: results.flutterPath?.available },
        { name: 'ADB in PATH', status: results.adbPath?.available },
        { name: 'Flutter Installation', status: flutterInstalls.length > 0 },
        { name: 'Android SDK', status: androidSdk !== null },
        { name: 'Connected Devices', status: results.devices }
    ];

    checks.forEach(check => {
        if (check.status === true) {
            colorLog('green', `✅ ${check.name}`);
        } else if (check.status === false) {
            colorLog('red', `❌ ${check.name}`);
        } else {
            colorLog('yellow', `⚠️  ${check.name} - Not available`);
        }
    });

    // Provide fix instructions if needed
    if (!results.flutterPath.available || !results.adbPath.available) {
        generatePathFixInstructions(flutterInstalls, androidSdk);
    }

    console.log('\n' + '='.repeat(50));

    if (results.flutterPath.available && results.adbPath.available) {
        colorLog('green', '🎉 All essential tools are available! You can run:');
        console.log('   npm run build-and-run');
    } else {
        colorLog('yellow', '⚠️  Setup incomplete. Please fix the issues above.');
        console.log('\nQuick fixes:');
        console.log('   npm run fix-flutter-path  # Automated PATH fix');
        console.log('   npm run test-flutter      # Test Flutter');
        console.log('   npm run test-adb          # Test ADB');
    }

    console.log('\n');
}

// Run the verification
main().catch(error => {
    colorLog('red', `Error during verification: ${error.message}`);
    process.exit(1);
});
