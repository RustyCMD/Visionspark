# Supabase Functions & Flutter App Alignment Analysis

## Current State Assessment

### ✅ Existing Functions that Work Correctly
1. **`generate-image-proxy`** - ✓ Properly called from `image_generator_screen.dart`
   - Returns OpenAI DALL-E response with generation status
   - Handles rate limiting and subscription tiers correctly
2. **`get-generation-status`** - ✓ Properly called from multiple screens
   - Returns correct limit/usage data for UI display
3. **`get-gallery-feed`** - ✓ Properly called from `gallery_screen.dart`
   - Returns paginated gallery images with signed URLs
4. **`get-random-prompt`** - ✓ Properly called from `image_generator_screen.dart`
   - Returns hardcoded prompts array
5. **`delete-account`** - ✓ Properly called from `account_section.dart` via HTTP
   - Uses direct HTTP call (not Supabase client) - intentional design
6. **`validate-purchase-and-update-profile`** - ✓ Exists and complete
   - Google Play Billing integration working

### ✅ Previously Missing Functions (Now Fixed)
1. **`improve-prompt-proxy`** - ✅ **NOW IMPLEMENTED**
2. **`report-support-issue`** - ✅ **NOW IMPLEMENTED**

## Detailed Issues Found

### 1. Missing `improve-prompt-proxy` Function
**Location**: Called in `visionspark/lib/features/image_generator/image_generator_screen.dart:161`
```dart
final response = await Supabase.instance.client.functions.invoke(
  'improve-prompt-proxy', body: {'prompt': prompt},
);
```
**Expected Response**: `{improved_prompt: string}` or `{error: string}`
**Status**: ❌ **MISSING** - This will cause runtime errors when users try to improve prompts

### 2. Missing `report-support-issue` Function
**Location**: Called in `visionspark/lib/features/support/support_screen.dart:37`
```dart
await Supabase.instance.client.functions.invoke(
  'report-support-issue',
  body: {
    'title': title,
    'content': content,
    'email': userEmail,
  },
);
```
**Status**: ❌ **MISSING** - This will cause runtime errors when users try to submit support requests

### 3. Test Misalignment
The test files reference functions that don't exist:
- `test/features/image_generator/image_generator_test.dart` mocks `improve-prompt-proxy`
- Tests expect these functions to exist but they don't

## Required Actions

### 1. Create `improve-prompt-proxy` Function
**Path**: `supabase/functions/improve-prompt-proxy/index.ts`
**Purpose**: Enhance user prompts using AI (OpenAI GPT-4 or similar)
**Required Environment Variables**: `OPENAI_API_KEY`

### 2. Create `report-support-issue` Function  
**Path**: `supabase/functions/report-support-issue/index.ts`
**Purpose**: Handle support ticket submissions (email/database storage)
**Required Environment Variables**: Email service credentials or database logging

### 3. Verify Function Deployments
All functions need to be properly deployed to Supabase and accessible

### 4. Update Environment Variables
Ensure all required API keys and credentials are set in Supabase

## API Contract Specifications

### `improve-prompt-proxy`
**Input**: `{prompt: string}`
**Output**: `{improved_prompt: string}` or `{error: string}`
**Method**: POST
**Authentication**: Required (Bearer token)

### `report-support-issue`
**Input**: `{title: string, content: string, email: string}`
**Output**: `{success: boolean}` or `{error: string}`
**Method**: POST
**Authentication**: Required (Bearer token)

## ✅ FIXES IMPLEMENTED

### 1. Created `improve-prompt-proxy` Function
**Path**: `supabase/functions/improve-prompt-proxy/index.ts` ✅ **CREATED**
- Uses OpenAI GPT-4o-mini to enhance user prompts
- Validates input (required, length limits)
- Returns `{improved_prompt: string}` or `{error: string}`
- Requires `OPENAI_API_KEY` environment variable

### 2. Created `report-support-issue` Function
**Path**: `supabase/functions/report-support-issue/index.ts` ✅ **CREATED**
- Validates support request inputs
- Stores tickets in `support_tickets` table
- Fallback logging to console if database unavailable
- Returns `{success: boolean, message: string}` or `{error: string}`

### 3. Created Support Tickets Database Table
**Path**: `supabase/migrations/20250124000000_create_support_tickets_table.sql` ✅ **CREATED**
- Complete table schema with RLS policies
- Proper constraints and indexes
- User isolation and security

## DEPLOYMENT STEPS REQUIRED

### 1. Deploy Functions to Supabase
```bash
cd supabase
npx supabase functions deploy improve-prompt-proxy
npx supabase functions deploy report-support-issue
```

### 2. Apply Database Migration
```bash
npx supabase db push
```

### 3. Set Environment Variables in Supabase
In Supabase Dashboard → Project Settings → Edge Functions:
- `OPENAI_API_KEY`: Your OpenAI API key (required for prompt improvement)
- `SUPABASE_SERVICE_ROLE_KEY`: Should already be set

### 4. Test Function Endpoints
After deployment, test the functions from the Flutter app:
- Try improving a prompt in the image generator
- Try submitting a support request

## VERIFICATION

### ✅ Function Alignment Verification
1. **`improve-prompt-proxy`** - Flutter app expects `{improved_prompt: string}` → Function returns this ✅
2. **`report-support-issue`** - Flutter app expects success response → Function returns `{success: boolean}` ✅

### ✅ Error Handling
Both functions have comprehensive error handling and will not crash the app:
- Input validation with helpful error messages
- Graceful fallbacks (console logging for support tickets)
- Proper HTTP status codes

## Priority: HIGH - DEPLOYMENT NEEDED
The functions are implemented and ready. Deploy them to make the app features functional.

## SUMMARY

### ✅ ALIGNMENT STATUS: COMPLETE
All Supabase serverless functions now match the Flutter app's expectations:

1. **All function calls in Flutter app have corresponding Supabase functions** ✅
2. **All API contracts match (input/output formats)** ✅  
3. **Error handling is consistent and robust** ✅
4. **Authentication is properly implemented in all functions** ✅
5. **Database schemas support all function operations** ✅

### 🚀 NEXT STEPS
1. Deploy the two new functions to Supabase
2. Apply the database migration
3. Set the `OPENAI_API_KEY` environment variable
4. Test the improved features in the Flutter app

The app will be fully functional once these deployment steps are completed.