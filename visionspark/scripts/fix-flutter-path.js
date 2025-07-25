#!/usr/bin/env node

/**
 * VisionSpark Flutter PATH Fix Script for Windows
 * Automatically detects and helps fix Flutter PATH issues
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
    cyan: '\x1b[36m'
};

function colorLog(color, message) {
    console.log(`${colors[color]}${message}${colors.reset}`);
}

function findFlutterInstallations() {
    const commonPaths = [
        'C:\\flutter',
        'C:\\src\\flutter',
        'C:\\tools\\flutter',
        path.join(os.homedir(), 'flutter'),
        path.join(os.homedir(), 'AppData', 'Local', 'flutter'),
        path.join(os.homedir(), 'Documents', 'flutter'),
        'D:\\flutter',
        'E:\\flutter'
    ];

    const found = [];
    for (const flutterPath of commonPaths) {
        const flutterBat = path.join(flutterPath, 'bin', 'flutter.bat');
        const flutterExe = path.join(flutterPath, 'bin', 'flutter.exe');
        
        if (fs.existsSync(flutterBat) || fs.existsSync(flutterExe)) {
            found.push({
                path: flutterPath,
                binPath: path.join(flutterPath, 'bin'),
                executable: fs.existsSync(flutterBat) ? flutterBat : flutterExe
            });
        }
    }

    return found;
}

function findAndroidSdk() {
    const commonPaths = [
        path.join(os.homedir(), 'AppData', 'Local', 'Android', 'Sdk'),
        'C:\\Android\\Sdk',
        'C:\\Users\\Public\\Android\\Sdk',
        path.join(os.homedir(), 'Android', 'Sdk'),
        'D:\\Android\\Sdk',
        'E:\\Android\\Sdk'
    ];

    for (const sdkPath of commonPaths) {
        const adbExe = path.join(sdkPath, 'platform-tools', 'adb.exe');
        if (fs.existsSync(adbExe)) {
            return {
                path: sdkPath,
                platformToolsPath: path.join(sdkPath, 'platform-tools'),
                adbPath: adbExe
            };
        }
    }

    return null;
}

function getCurrentPath() {
    try {
        const output = execSync('echo %PATH%', { 
            encoding: 'utf8', 
            shell: 'cmd.exe',
            windowsHide: true 
        });
        return output.trim().split(';');
    } catch (error) {
        colorLog('red', '❌ Failed to get current PATH');
        return [];
    }
}

function testFlutterCommand(flutterBinPath) {
    try {
        const flutterExe = path.join(flutterBinPath, 'flutter.bat');
        const output = execSync(`"${flutterExe}" --version`, { 
            encoding: 'utf8', 
            stdio: 'pipe',
            windowsHide: true,
            timeout: 30000
        });
        return { success: true, output: output.trim() };
    } catch (error) {
        return { success: false, error: error.message };
    }
}

function generateBatchScript(flutterBinPath, androidPlatformToolsPath) {
    const scriptContent = `@echo off
echo Setting up Flutter and Android SDK paths...

:: Add Flutter to PATH for current session
set "PATH=${flutterBinPath};%PATH%"

${androidPlatformToolsPath ? `:: Add Android platform-tools to PATH for current session
set "PATH=${androidPlatformToolsPath};%PATH%"` : ''}

echo ✅ Paths set for current session!
echo.
echo Testing Flutter...
flutter --version
echo.
${androidPlatformToolsPath ? `echo Testing ADB...
adb version
echo.` : ''}

echo 🎉 Setup complete! You can now run Flutter commands.
echo.
echo To make this permanent, add these paths to your system PATH:
echo   ${flutterBinPath}
${androidPlatformToolsPath ? `echo   ${androidPlatformToolsPath}` : ''}
echo.
echo Or run this script again when you need Flutter commands.
pause
`;

    const scriptPath = path.join(process.cwd(), 'setup-flutter-path.bat');
    fs.writeFileSync(scriptPath, scriptContent);
    return scriptPath;
}

function generatePowerShellScript(flutterBinPath, androidPlatformToolsPath) {
    const scriptContent = `# VisionSpark Flutter PATH Setup Script
Write-Host "Setting up Flutter and Android SDK paths..." -ForegroundColor Cyan

# Add Flutter to PATH for current session
$env:PATH = "${flutterBinPath};$env:PATH"

${androidPlatformToolsPath ? `# Add Android platform-tools to PATH for current session
$env:PATH = "${androidPlatformToolsPath};$env:PATH"` : ''}

Write-Host "✅ Paths set for current session!" -ForegroundColor Green
Write-Host ""

Write-Host "Testing Flutter..." -ForegroundColor Blue
flutter --version
Write-Host ""

${androidPlatformToolsPath ? `Write-Host "Testing ADB..." -ForegroundColor Blue
adb version
Write-Host ""` : ''}

Write-Host "🎉 Setup complete! You can now run Flutter commands." -ForegroundColor Green
Write-Host ""
Write-Host "To make this permanent, add these paths to your system PATH:" -ForegroundColor Yellow
Write-Host "  ${flutterBinPath}" -ForegroundColor White
${androidPlatformToolsPath ? `Write-Host "  ${androidPlatformToolsPath}" -ForegroundColor White` : ''}
Write-Host ""
Write-Host "Or run this script again when you need Flutter commands." -ForegroundColor Yellow
Read-Host "Press Enter to continue"
`;

    const scriptPath = path.join(process.cwd(), 'setup-flutter-path.ps1');
    fs.writeFileSync(scriptPath, scriptContent);
    return scriptPath;
}

async function main() {
    console.log('\n' + '='.repeat(50));
    colorLog('cyan', '   Flutter PATH Fix Tool');
    console.log('='.repeat(50));

    // Check if Flutter is already in PATH
    try {
        execSync('flutter --version', { 
            stdio: 'pipe', 
            windowsHide: true 
        });
        colorLog('green', '\n✅ Flutter is already available in PATH!');
        console.log('No fix needed. You can run: npm run build-and-run');
        return;
    } catch (error) {
        colorLog('yellow', '\n⚠️  Flutter not found in PATH. Searching for installations...');
    }

    // Find Flutter installations
    const flutterInstalls = findFlutterInstallations();
    if (flutterInstalls.length === 0) {
        colorLog('red', '\n❌ No Flutter installations found!');
        console.log('\n📥 Please install Flutter first:');
        console.log('   1. Download from: https://flutter.dev/docs/get-started/install/windows');
        console.log('   2. Extract to C:\\flutter');
        console.log('   3. Run this script again');
        return;
    }

    colorLog('green', `\n✅ Found ${flutterInstalls.length} Flutter installation(s):`);
    flutterInstalls.forEach((install, index) => {
        console.log(`   ${index + 1}. ${install.path}`);
    });

    // Find Android SDK
    const androidSdk = findAndroidSdk();
    if (androidSdk) {
        colorLog('green', `\n✅ Found Android SDK: ${androidSdk.path}`);
    } else {
        colorLog('yellow', '\n⚠️  Android SDK not found in common locations');
    }

    // Use the first Flutter installation found
    const selectedFlutter = flutterInstalls[0];
    colorLog('blue', `\n🔧 Using Flutter installation: ${selectedFlutter.path}`);

    // Test the Flutter installation
    colorLog('blue', '\n🧪 Testing Flutter installation...');
    const testResult = testFlutterCommand(selectedFlutter.binPath);
    if (!testResult.success) {
        colorLog('red', '❌ Flutter installation appears to be corrupted');
        console.log(`Error: ${testResult.error}`);
        return;
    }
    colorLog('green', '✅ Flutter installation is working');

    // Generate helper scripts
    colorLog('blue', '\n📝 Generating helper scripts...');
    
    const batchScript = generateBatchScript(
        selectedFlutter.binPath, 
        androidSdk?.platformToolsPath
    );
    const psScript = generatePowerShellScript(
        selectedFlutter.binPath, 
        androidSdk?.platformToolsPath
    );

    colorLog('green', '✅ Helper scripts created:');
    console.log(`   - ${batchScript}`);
    console.log(`   - ${psScript}`);

    // Provide instructions
    console.log('\n' + '='.repeat(50));
    colorLog('cyan', '   NEXT STEPS');
    console.log('='.repeat(50));

    console.log('\n🚀 Quick Fix (Temporary):');
    console.log('   Run one of these scripts to set PATH for current session:');
    colorLog('green', '   • setup-flutter-path.bat     (Command Prompt)');
    colorLog('green', '   • setup-flutter-path.ps1     (PowerShell)');

    console.log('\n🔧 Permanent Fix (Recommended):');
    console.log('   1. Press Win + R, type "sysdm.cpl" and press Enter');
    console.log('   2. Click "Environment Variables" button');
    console.log('   3. Under "User variables", find "Path" and click "Edit"');
    console.log('   4. Click "New" and add:');
    colorLog('green', `      ${selectedFlutter.binPath}`);
    if (androidSdk) {
        colorLog('green', `      ${androidSdk.platformToolsPath}`);
    }
    console.log('   5. Click "OK" on all dialogs');
    console.log('   6. Restart Command Prompt/PowerShell');
    console.log('   7. Test with: flutter --version');

    console.log('\n💡 After fixing PATH, you can run:');
    colorLog('green', '   npm run test-adb         # Test ADB installation');
    colorLog('green', '   npm run check-device     # Check connected devices');
    colorLog('green', '   npm run build-and-run    # Complete build workflow');

    console.log('\n📚 For more help:');
    console.log('   npm run help');
    console.log('   npm run setup');

    console.log('\n');
}

// Run the fix tool
main().catch(error => {
    colorLog('red', `Error: ${error.message}`);
    process.exit(1);
});
