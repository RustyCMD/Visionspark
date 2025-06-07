/// <reference types="https://esm.sh/v135/@supabase/functions-js@2.4.1/src/edge-runtime.d.ts" />
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { create as createJWT } from "https://deno.land/x/djwt@v2.8/mod.ts"; // Example JWT library
// import { corsHeaders } from '../_shared/cors.ts'; // Removed

// Add Google Play Billing API client
// @ts-ignore
// const {GooglePlayBilling} = require('@google-cloud/billing'); // TODO: Find Deno-compatible way to use Google Play Billing

// Inlined CORS Headers
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// --- Google API Config (Store securely as environment variables) ---
const GOOGLE_SERVICE_ACCOUNT_EMAIL = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_EMAIL')!;
const GOOGLE_PRIVATE_KEY_PEM = Deno.env.get('GOOGLE_PRIVATE_KEY_PEM')!; // Ensure PEM format, newlines as \\n
const APP_PACKAGE_NAME = 'app.visionspark.app';
// ---

async function getGoogleAccessToken() {
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: GOOGLE_SERVICE_ACCOUNT_EMAIL,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    exp: now + 3600, // 1 hour
    iat: now,
  };

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
    throw new Error(`Failed to get Google access token: ${response.status} ${errorBody}`);
  }
  const data = await response.json();
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


async function validateGooglePlayPurchase(productId: string, purchaseToken: string, accessToken: string): Promise<boolean> {
  // For subscriptions, productId is the subscriptionId/SKU
  const subscriptionId = productId;
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${APP_PACKAGE_NAME}/purchases/subscriptions/${subscriptionId}/tokens/${purchaseToken}`;

  const response = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    console.error(`Google Play API Error: ${response.status}`, await response.text());
    return false; // Or throw a more specific error
  }

  const purchaseData = await response.json();

  // --- Validate purchaseData for Subscriptions ---
  // Check if the subscription is active (not expired)
  // paymentState: 0 = Pending, 1 = Active, 2 = Grace period, (other states might exist for issues)
  // autoRenewing: boolean
  if (purchaseData.expiryTimeMillis && parseInt(purchaseData.expiryTimeMillis) > Date.now()) {
    // Optionally, you might also want to check purchaseData.paymentState if it's critical
    // e.g., if (purchaseData.paymentState === 1 /* ACTIVE */ || purchaseData.paymentState === 2 /* GRACE PERIOD */)
    // For simplicity, primary check is expiryTimeMillis
    
    // Optional: Acknowledge the subscription if not yet acknowledged (usually for the first purchase or after recovery)
    // The `isAcknowledged` field might not be directly on `purchaseData` for subscriptions in the same way.
    // Acknowledgment status is typically inferred or handled based on whether you've called acknowledge.
    // The API `purchases.subscriptions.get` returns `acknowledgementState` (0: Yet to be acknowledged, 1: Acknowledged)
    if (purchaseData.acknowledgementState === 0) { // 0 means not acknowledged
        console.log(`Subscription ${subscriptionId} for token ${purchaseToken} needs acknowledgement.`);
        // await acknowledgeGooglePlaySubscription(subscriptionId, purchaseToken, accessToken);
    }
    return true;
  }

  console.log(`Subscription ${subscriptionId} for token ${purchaseToken} is not valid or has expired. Expiry: ${purchaseData.expiryTimeMillis}, Payment State: ${purchaseData.paymentState}, Ack State: ${purchaseData.acknowledgementState}`);
  return false;
}

// Optional: Function to acknowledge a subscription
// async function acknowledgeGooglePlaySubscription(subscriptionId: string, purchaseToken: string, accessToken: string) {
//   const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${APP_PACKAGE_NAME}/purchases/subscriptions/${subscriptionId}/tokens/${purchaseToken}:acknowledge`;

//   const response = await fetch(url, {
//     method: 'POST',
// ... existing code ...
//   console.log("Subscription acknowledged successfully:", subscriptionId);
//   return true;
// }


serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    );

    const { productId, purchaseToken } = await req.json();
    if (!productId) {
      throw new Error('Product ID is required.');
    }
    if (!purchaseToken) {
      throw new Error('Purchase token is required.');
    }

    const { data: { user } } = await supabaseClient.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: 'User not authenticated.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      });
    }

    // --- Perform Google Play Validation ---
    let googleAccessToken;
    try {
        googleAccessToken = await getGoogleAccessToken();
    } catch (tokenError) {
        console.error("Error getting Google Access Token:", tokenError);
        throw new Error("Failed to authenticate with Google Play services.");
    }

    const isPurchaseValid = await validateGooglePlayPurchase(productId, purchaseToken, googleAccessToken);
    if (!isPurchaseValid) {
      throw new Error('Invalid purchase or failed to validate with Google Play.');
    }
    // --- End Google Play Validation ---


    let tier: string | null = null;
    let isActive = false;
    let expiresAt: string | null = null;
    const now = new Date();
    const futureDate = new Date(now);
    futureDate.setDate(now.getDate() + 30); 

    if (productId === 'monthly_30_generations') {
      tier = 'monthly_30';
      isActive = true;
      expiresAt = futureDate.toISOString();
    } else if (productId === 'monthly_unlimited_generations') {
      tier = 'monthly_unlimited';
      isActive = true;
      expiresAt = futureDate.toISOString();
    } else {
      // If purchase was validated by Google but product ID is unknown to your system here
      console.warn(`Validated purchase for unknown productId: ${productId}`);
      // Decide how to handle: maybe a generic entitlement or log for review
      // For now, returning an error as original logic did.
      return new Response(JSON.stringify({ error: 'Product ID recognized by Google but not configured in this function.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      });
    }

    const { error: updateError } = await supabaseClient
      .from('profiles')
      .update({
        current_subscription_tier: tier,
        subscription_active: isActive,
        subscription_expires_at: expiresAt,
      })
      .eq('id', user.id);

    if (updateError) {
      console.error('Error updating profile with subscription:', updateError);
      throw new Error(`Failed to update profile: ${updateError.message}`);
    }

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