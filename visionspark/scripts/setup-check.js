#!/usr/bin/env node

/**
 * VisionSpark Setup Verification Script
 * Checks all prerequisites for Flutter Android development
 */

const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

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

function checkCommand(command, name, installUrl = '') {
    try {
        const output = execSync(command, { encoding: 'utf8', stdio: 'pipe' });
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

function checkFile(filePath, description) {
    if (fs.existsSync(filePath)) {
        colorLog('green', `✅ ${description} exists`);
        return true;
    } else {
        colorLog('red', `❌ ${description} not found`);
        return false;
    }
}

async function checkDevices() {
    try {
        const output = execSync('adb devices -l', { encoding: 'utf8', stdio: 'pipe' });
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
        colorLog('red', '❌ Failed to check devices');
        return false;
    }
}

async function checkFlutterDoctor() {
    try {
        colorLog('blue', '🔍 Running Flutter Doctor...');
        const output = execSync('flutter doctor', { encoding: 'utf8', stdio: 'pipe' });
        console.log(output);
        return true;
    } catch (error) {
        colorLog('red', '❌ Flutter Doctor failed');
        console.log(error.stdout || error.message);
        return false;
    }
}

async function checkProjectStructure() {
    const requiredFiles = [
        { path: 'pubspec.yaml', desc: 'Flutter project configuration' },
        { path: 'lib/main.dart', desc: 'Main Flutter application file' },
        { path: 'android/app/build.gradle', desc: 'Android build configuration' },
        { path: 'android/app/src/main/AndroidManifest.xml', desc: 'Android manifest' }
    ];

    let allPresent = true;
    colorLog('blue', '📁 Checking project structure...');
    
    for (const file of requiredFiles) {
        if (!checkFile(file.path, file.desc)) {
            allPresent = false;
        }
    }
    
    return allPresent;
}

async function main() {
    console.log('\n========================================');
    colorLog('cyan', '   VisionSpark Setup Verification');
    console.log('========================================\n');

    let allGood = true;
    const results = {};

    // Check Node.js
    colorLog('blue', '1. Checking Node.js...');
    results.node = checkCommand('node --version', 'Node.js', 'https://nodejs.org/');
    if (results.node.available) {
        console.log(`   Version: ${results.node.output}`);
    }

    // Check npm
    colorLog('blue', '\n2. Checking npm...');
    results.npm = checkCommand('npm --version', 'npm');
    if (results.npm.available) {
        console.log(`   Version: ${results.npm.output}`);
    }

    // Check Flutter
    colorLog('blue', '\n3. Checking Flutter...');
    results.flutter = checkCommand('flutter --version', 'Flutter', 'https://flutter.dev/docs/get-started/install');

    // Check ADB
    colorLog('blue', '\n4. Checking ADB...');
    results.adb = checkCommand('adb version', 'ADB (Android Debug Bridge)', 'Install Android SDK or Android Studio');

    // Check connected devices
    colorLog('blue', '\n5. Checking connected devices...');
    results.devices = await checkDevices();

    // Check project structure
    colorLog('blue', '\n6. Checking project structure...');
    results.project = await checkProjectStructure();

    // Run Flutter Doctor if Flutter is available
    if (results.flutter.available) {
        colorLog('blue', '\n7. Running Flutter Doctor...');
        results.doctor = await checkFlutterDoctor();
    }

    // Summary
    console.log('\n========================================');
    colorLog('cyan', '   SETUP VERIFICATION SUMMARY');
    console.log('========================================\n');

    const checks = [
        { name: 'Node.js', status: results.node?.available },
        { name: 'npm', status: results.npm?.available },
        { name: 'Flutter', status: results.flutter?.available },
        { name: 'ADB', status: results.adb?.available },
        { name: 'Connected Devices', status: results.devices },
        { name: 'Project Structure', status: results.project },
        { name: 'Flutter Doctor', status: results.doctor }
    ];

    checks.forEach(check => {
        if (check.status === true) {
            colorLog('green', `✅ ${check.name}`);
        } else if (check.status === false) {
            colorLog('red', `❌ ${check.name}`);
            allGood = false;
        } else {
            colorLog('yellow', `⚠️  ${check.name} - Not checked`);
        }
    });

    console.log('\n========================================\n');

    if (allGood && results.devices && results.flutter.available && results.adb.available) {
        colorLog('green', '🎉 All checks passed! You\'re ready to build and run VisionSpark!');
        console.log('\nNext steps:');
        console.log('  npm run build-and-run     # Complete build and run workflow');
        console.log('  npm run help              # View all available commands');
    } else {
        colorLog('yellow', '⚠️  Some issues found. Please address the failed checks above.');
        console.log('\nCommon solutions:');
        if (!results.flutter?.available) {
            console.log('  • Install Flutter: https://flutter.dev/docs/get-started/install');
        }
        if (!results.adb?.available) {
            console.log('  • Install Android Studio or Android SDK');
            console.log('  • Add platform-tools to your PATH');
        }
        if (!results.devices) {
            console.log('  • Connect your Android device via USB');
            console.log('  • Enable USB debugging in Developer Options');
            console.log('  • Accept the "Allow USB debugging" prompt');
        }
    }

    console.log('\nFor detailed help, run: npm run help\n');
}

// Run the verification
main().catch(error => {
    colorLog('red', `Error during verification: ${error.message}`);
    process.exit(1);
});
