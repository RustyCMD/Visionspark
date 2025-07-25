# Google Sign-In Production Setup Instructions

## Current Issue
Google Sign-In works in development but fails in production release from Google Play Store.

## Root Cause
The OAuth client ID configuration in Firebase/Google Cloud Console is missing the release keystore SHA-1 fingerprint.

## Your Keystore Fingerprints
- **Debug SHA-1:** `F0:AA:A4:8D:5C:12:47:FB:6A:EE:1C:2B:07:89:1F:1A:A8:B7:EC:7F`
- **Release SHA-1:** `7A:AA:7B:A3:AA:D9:81:90:E4:4C:D2:32:AF:A2:E9:5B:A2:23:EE:5C`

## Step-by-Step Fix

### 1. Firebase Console Setup
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: `vision-spark`
3. Go to Project Settings → General tab
4. Find your Android app (`app.visionspark.app`)
5. Add SHA certificate fingerprints:
   - Add release SHA-1: `7A:AA:7B:A3:AA:D9:81:90:E4:4C:D2:32:AF:A2:E9:5B:A2:23:EE:5C`
   - Ensure debug SHA-1 is also there: `F0:AA:A4:8D:5C:12:47:FB:6A:EE:1C:2B:07:89:1F:1A:A8:B7:EC:7F`

### 2. Google Cloud Console Setup
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select project: `vision-spark`
3. Navigate to APIs & Services → Credentials
4. Create OAuth 2.0 Client ID for Android Release:
   - Application type: Android
   - Name: `VisionSpark Android Release`
   - Package name: `app.visionspark.app`
   - SHA-1: `7A:AA:7B:A3:AA:D9:81:90:E4:4C:D2:32:AF:A2:E9:5B:A2:23:EE:5C`
5. Create OAuth 2.0 Client ID for Android Debug (if not exists):
   - Application type: Android
   - Name: `VisionSpark Android Debug`
   - Package name: `app.visionspark.app`
   - SHA-1: `F0:AA:A4:8D:5C:12:47:FB:6A:EE:1C:2B:07:89:1F:1A:A8:B7:EC:7F`

### 3. Update google-services.json
1. Return to Firebase Console → Project Settings
2. Download the updated `google-services.json`
3. Replace `visionspark/android/app/google-services.json` with the new file
4. The new file should contain multiple OAuth client entries

### 4. Verify Configuration
Current OAuth client ID in code: `825189008537-9lpvr3no63a79k8hppkhjfm0ha4mtflo.apps.googleusercontent.com`
This should remain the same (it's the web client ID for server-side auth).

### 5. Rebuild and Test
1. Clean and rebuild the app:
   ```bash
   flutter clean
   flutter pub get
   flutter build appbundle --release
   ```
2. Upload new AAB to Google Play Console
3. Test the production app

## Important Notes
- The serverClientId in your Flutter code should remain the same
- You need separate Android OAuth client IDs for debug and release builds
- The web OAuth client ID (current one) is used for server-side authentication
- After updating Firebase configuration, it may take a few minutes to propagate

## Current Code Configuration
File: `lib/auth/auth_screen.dart`
```dart
final googleSignIn = GoogleSignIn(
  serverClientId: '825189008537-9lpvr3no63a79k8hppkhjfm0ha4mtflo.apps.googleusercontent.com'
);
```
This configuration is correct and should not be changed.

## Troubleshooting
If Google Sign-In still fails after these steps:
1. Verify SHA-1 fingerprints are correctly added in Firebase
2. Ensure OAuth client IDs are created for both debug and release
3. Check that the package name matches exactly: `app.visionspark.app`
4. Wait 10-15 minutes for configuration changes to propagate
5. Clear app data and try again
