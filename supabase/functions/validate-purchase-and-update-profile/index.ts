/// <reference types="https://esm.sh/v135/@supabase/functions-js@2.4.1/src/edge-runtime.d.ts" />
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { create as createJWT } from "https://deno.land/x/djwt@v2.8/mod.ts"; // Example JWT library
// import { corsHeaders } from '../_shared/cors.ts'; // Removed

import { corsHeaders } from '../_shared/cors.ts';

// --- Google API Config (Store securely as environment variables) ---
const GOOGLE_SERVICE_ACCOUNT_EMAIL = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_EMAIL')!;
const GOOGLE_PRIVATE_KEY_PEM = Deno.env.get('GOOGLE_PRIVATE_KEY_PEM')!; // Ensure PEM format, newlines as \\n
const GOOGLE_CLOUD_PROJECT_ID = Deno.env.get('GOOGLE_CLOUD_PROJECT_ID') || 'vision-spark'; // Fallback to known project ID
const GOOGLE_SERVICE_ACCOUNT_CLIENT_ID = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_CLIENT_ID');
const GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY_ID = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY_ID');
const APP_PACKAGE_NAME = 'app.visionspark.app';
const GRACE_PERIOD_MILLISECONDS = 3 * 24 * 60 * 60 * 1000; // 3 days

// Validation: Ensure critical variables are set
if (!GOOGLE_SERVICE_ACCOUNT_EMAIL) {
  throw new Error('GOOGLE_SERVICE_ACCOUNT_EMAIL environment variable is required');
}
if (!GOOGLE_PRIVATE_KEY_PEM) {
  throw new Error('GOOGLE_PRIVATE_KEY_PEM environment variable is required');
}
// ---

// Define a new interface for the validation result
interface GooglePlaySubscriptionValidationResult {
  isValid: boolean;
  purchaseData?: any; // The raw purchase data from Google, contains expiryTimeMillis, acknowledgementState etc.
  error?: string;
}

async function getGoogleAccessToken() {
  console.log('🔐 Initializing Google Service Account authentication...');
  console.log(`📧 Service Account Email: ${GOOGLE_SERVICE_ACCOUNT_EMAIL}`);
  console.log(`🏗️ Google Cloud Project ID: ${GOOGLE_CLOUD_PROJECT_ID}`);
  console.log(`📦 App Package Name: ${APP_PACKAGE_NAME}`);

  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: GOOGLE_SERVICE_ACCOUNT_EMAIL,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600, // 1 hour
    iat: now,
  };

  console.log('🔑 Creating JWT for Google OAuth...');

  // Import private key (ensure it's in the correct PKCS#8 PEM format)
  // The private key string from env var might need newlines properly escaped or handled
  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToBinary(GOOGLE_PRIVATE_KEY_PEM.replace(/\\n/g, '\n')),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const jwt = await createJWT(header, payload, privateKey);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`❌ Google OAuth Token Error: ${response.status}`);
    console.error(`❌ Error Details: ${errorBody}`);
    console.error(`❌ Service Account: ${GOOGLE_SERVICE_ACCOUNT_EMAIL}`);
    console.error(`❌ Project ID: ${GOOGLE_CLOUD_PROJECT_ID}`);
    throw new Error(`Failed to get Google access token: ${response.status} ${errorBody}`);
  }
  const data = await response.json();
  console.log('✅ Google access token obtained successfully');
  return data.access_token;
}

// Helper to convert PEM to ArrayBuffer
function pemToBinary(pem: string) {
  const lines = pem.split('\n');
  let base64 = '';
  for (const line of lines) {
    if (line.includes('-----BEGIN') || line.includes('-----END') || line.trim() === '') {
      continue;
    }
    base64 += line.trim();
  }
  const binaryString = atob(base64);
  const len = binaryString.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes.buffer;
}


async function validateGooglePlayPurchase(productId: string, purchaseToken: string, accessToken: string): Promise<GooglePlaySubscriptionValidationResult> {
  // For subscriptions, productId is the subscriptionId/SKU
  const subscriptionId = productId;
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${APP_PACKAGE_NAME}/purchases/subscriptions/${subscriptionId}/tokens/${purchaseToken}?access_token=${accessToken}`;

  console.log('🔍 Validating Google Play purchase...');
  console.log(`📦 Package Name: ${APP_PACKAGE_NAME}`);
  console.log(`🏷️ Subscription ID: ${subscriptionId}`);
  console.log(`🎫 Purchase Token: ${purchaseToken.substring(0, 20)}...`);
  console.log(`🌐 API URL: ${url.substring(0, 100)}...`);

  const response = await fetch(url, {
    // headers: { // Headers can also be used
    //   'Authorization': `Bearer ${accessToken}`,
    // },
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`❌ Google Play API Error: ${response.status}`);
    console.error(`❌ Error Details: ${errorText}`);
    console.error(`❌ Package Name Used: ${APP_PACKAGE_NAME}`);
    console.error(`❌ Project ID: ${GOOGLE_CLOUD_PROJECT_ID}`);
    console.error(`❌ Service Account: ${GOOGLE_SERVICE_ACCOUNT_EMAIL}`);

    // Check for specific error types
    if (response.status === 403) {
      console.error(`❌ 403 Forbidden - Possible causes:`);
      console.error(`   • Service account doesn't have Google Play Developer API access`);
      console.error(`   • Package name mismatch: ${APP_PACKAGE_NAME}`);
      console.error(`   • Google Play Console not linked to project: ${GOOGLE_CLOUD_PROJECT_ID}`);
    }

    return { isValid: false, error: `Google Play API Error (${response.status}): ${errorText}` };
  }

  const purchaseData = await response.json();

  // --- Validate purchaseData for Subscriptions ---
  if (purchaseData.expiryTimeMillis && (parseInt(purchaseData.expiryTimeMillis) + GRACE_PERIOD_MILLISECONDS) > Date.now()) {
    // Successfully validated with Google (considering grace period for isValid flag)
    return { isValid: true, purchaseData: purchaseData };
  }

  console.log(`Subscription ${subscriptionId} for token ${purchaseToken} is not valid or has expired (even with grace period). Expiry: ${purchaseData.expiryTimeMillis}, Payment State: ${purchaseData.paymentState}, Ack State: ${purchaseData.acknowledgementState}`);
  return { isValid: false, purchaseData: purchaseData, error: 'Subscription is not valid or has expired.' };
}

// Function to acknowledge a subscription
async function acknowledgeGooglePlaySubscription(subscriptionId: string, purchaseToken: string, accessToken: string): Promise<boolean> {
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${APP_PACKAGE_NAME}/purchases/subscriptions/${subscriptionId}/tokens/${purchaseToken}:acknowledge`;

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({}) // Body can be empty for acknowledge
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error(`Failed to acknowledge subscription ${subscriptionId}: ${response.status}`, errorText);
    // Depending on policy, you might want to throw an error or just log and return false
    return false; 
  }
  console.log("Subscription acknowledged successfully:", subscriptionId);
  return true;
}


serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    console.log('🔍 Purchase validation request received');

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    );

    const requestBody = await req.json();
    const { productId, purchaseToken, source } = requestBody;

    console.log(`📦 Product ID: ${productId}`);
    console.log(`🎫 Purchase Token: ${purchaseToken ? purchaseToken.substring(0, 20) + '...' : 'null'}`);
    console.log(`📱 Source: ${source}`);

    if (!productId) {
      console.error('❌ Missing Product ID');
      throw new Error('Product ID is required.');
    }
    if (!purchaseToken) {
      console.error('❌ Missing Purchase Token');
      throw new Error('Purchase token is required.');
    }

    const { data: { user } } = await supabaseClient.auth.getUser();
    if (!user) {
      console.error('❌ User not authenticated');
      return new Response(JSON.stringify({ error: 'User not authenticated.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      });
    }

    console.log(`👤 User authenticated: ${user.id}`);

    // --- Perform Google Play Validation ---
    console.log('🔑 Getting Google Access Token...');
    let googleAccessToken;
    try {
        googleAccessToken = await getGoogleAccessToken();
        console.log('✅ Google Access Token obtained successfully');
    } catch (tokenError) {
        console.error("❌ Error getting Google Access Token:", tokenError);
        throw new Error("Failed to authenticate with Google Play services.");
    }

    console.log('🔍 Validating purchase with Google Play...');
    const validationResult = await validateGooglePlayPurchase(productId, purchaseToken, googleAccessToken);

    if (!validationResult.isValid) {
      console.error('❌ Google Play validation failed:', validationResult.error);
      throw new Error(validationResult.error || 'Invalid purchase or failed to validate with Google Play.');
    }
    console.log('✅ Google Play validation successful');
    // --- End Google Play Validation ---

    // --- Acknowledge if necessary ---
    if (validationResult.purchaseData && validationResult.purchaseData.acknowledgementState === 0) {
      console.log(`Subscription ${productId} needs acknowledgement. Attempting to acknowledge...`);
      const ackSuccess = await acknowledgeGooglePlaySubscription(productId, purchaseToken, googleAccessToken);
      if (!ackSuccess) {
        // Log the error but proceed with entitlement update as validation was successful
        console.warn(`Failed to acknowledge subscription ${productId}, but entitlement will still be granted as validation passed.`);
        // You might want to implement a retry mechanism for acknowledgement later
      }
    }
    // --- End Acknowledgement ---

    let tier: string | null = null;
    let isActive = false;
    let expiresAt: string | null = null; // This will now come from Google
    let cycleStartDate: string | null = null; // For subscription_cycle_start_date

    // Use expiryTimeMillis from Google's response
    if (validationResult.purchaseData && validationResult.purchaseData.expiryTimeMillis) {
      const actualExpiryTimeMillis = parseInt(validationResult.purchaseData.expiryTimeMillis);
      expiresAt = new Date(actualExpiryTimeMillis).toISOString(); // Store REAL expiry from Google
      
      // isActive considers the grace period
      isActive = (actualExpiryTimeMillis + GRACE_PERIOD_MILLISECONDS) > Date.now();

      // Set cycleStartDate from Google's startTimeMillis if available, otherwise current time
      if (validationResult.purchaseData.startTimeMillis) {
        cycleStartDate = new Date(parseInt(validationResult.purchaseData.startTimeMillis)).toISOString();
      } else {
        console.warn("startTimeMillis not found in Google's response, using current time as cycle start date.");
        cycleStartDate = new Date().toISOString();
      }

    } else {
      // Fallback or error if expiryTimeMillis is missing after successful validation (should not happen)
      console.error("ExpiryTimeMillis missing from Google's response despite successful validation!");
      throw new Error("Failed to determine subscription expiry from Google Play.");
    }
    
    // Determine tier based on productId
    if (productId === 'monthly_unlimited_generations') {
      tier = 'monthly_unlimited_generations';
    } else {
      console.warn(`Validated purchase for unknown productId in this function logic: ${productId}. Tier will be null.`);
      // Allow entitlement if Google validated it, but the tier might not be specifically handled.
      // Or, throw an error if strict productId matching is required for tier assignment.
      // For now, tier will remain null, and isActive/expiresAt from Google will be used.
      // The DB update will proceed with a null tier if not matched.
    }
    
    // If tier is still null but purchase was Google-valid and has expiry, set isActive
    if (tier === null && isActive && expiresAt) {
        console.log(`Purchase for productId ${productId} is valid and active until ${expiresAt}, but not mapped to a specific tier in this function. User will get general active status.`);
    }

    const updatePayload: {
      current_subscription_tier: string | null;
      subscription_active: boolean;
      subscription_expires_at: string | null;
      subscription_cycle_start_date?: string | null; // Optional
    } = {
      current_subscription_tier: tier,
      subscription_active: isActive,
      subscription_expires_at: expiresAt,
    };

    if (isActive && cycleStartDate) { // Only set cycle start date if the subscription is active
        updatePayload.subscription_cycle_start_date = cycleStartDate;
    }

    console.log('💾 Updating user profile with subscription data:', JSON.stringify(updatePayload, null, 2));

    const { error: updateError } = await supabaseClient
      .from('profiles')
      .update(updatePayload)
      .eq('id', user.id);

    if (updateError) {
      console.error('❌ Error updating profile with subscription:', updateError);
      throw new Error(`Failed to update profile: ${updateError.message}`);
    }

    console.log('✅ Profile updated successfully');

    return new Response(JSON.stringify({ success: true, message: 'Subscription activated and profile updated.' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    });
  } catch (error) {
    console.error('Error in validate-purchase function:', error);
    return new Response(JSON.stringify({ error: error.message || 'An unexpected error occurred.' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    });
  }
}); 