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
  console.error('❌ MISSING: GOOGLE_SERVICE_ACCOUNT_EMAIL environment variable');
  throw new Error('GOOGLE_SERVICE_ACCOUNT_EMAIL environment variable is required');
}
if (!GOOGLE_PRIVATE_KEY_PEM) {
  console.error('❌ MISSING: GOOGLE_PRIVATE_KEY_PEM environment variable');
  throw new Error('GOOGLE_PRIVATE_KEY_PEM environment variable is required');
}

// Log configuration status (without sensitive data)
console.log('✅ Google Play API Configuration Status:');
console.log(`   📧 Service Account Email: ${GOOGLE_SERVICE_ACCOUNT_EMAIL ? 'SET' : 'MISSING'}`);
console.log(`   🔑 Private Key: ${GOOGLE_PRIVATE_KEY_PEM ? 'SET' : 'MISSING'}`);
console.log(`   🏗️ Project ID: ${GOOGLE_CLOUD_PROJECT_ID || 'USING_DEFAULT'}`);
console.log(`   📦 Package Name: ${APP_PACKAGE_NAME}`);
console.log(`   ⏰ Grace Period: ${GRACE_PERIOD_MILLISECONDS}ms (${GRACE_PERIOD_MILLISECONDS / (24 * 60 * 60 * 1000)} days)`);
// ---

// Define a new interface for the validation result
interface GooglePlaySubscriptionValidationResult {
  isValid: boolean;
  purchaseData?: any; // The raw purchase data from Google, contains expiryTimeMillis, acknowledgementState etc.
  error?: string;
}

// Comprehensive error classification system
enum ErrorCode {
  // Validation Errors (non-retryable)
  MISSING_PRODUCT_ID = 'MISSING_PRODUCT_ID',
  MISSING_PURCHASE_TOKEN = 'MISSING_PURCHASE_TOKEN',
  USER_NOT_AUTHENTICATED = 'USER_NOT_AUTHENTICATED',
  INVALID_PURCHASE = 'INVALID_PURCHASE',
  EXPIRED_PURCHASE = 'EXPIRED_PURCHASE',

  // Network/API Errors (retryable)
  GOOGLE_AUTH_FAILED = 'GOOGLE_AUTH_FAILED',
  GOOGLE_API_TIMEOUT = 'GOOGLE_API_TIMEOUT',
  GOOGLE_API_RATE_LIMIT = 'GOOGLE_API_RATE_LIMIT',
  GOOGLE_API_SERVER_ERROR = 'GOOGLE_API_SERVER_ERROR',

  // Database Errors (retryable)
  DATABASE_CONNECTION_ERROR = 'DATABASE_CONNECTION_ERROR',
  DATABASE_TIMEOUT = 'DATABASE_TIMEOUT',
  DATABASE_CONSTRAINT_ERROR = 'DATABASE_CONSTRAINT_ERROR',
  PROFILE_UPDATE_FAILED = 'PROFILE_UPDATE_FAILED',

  // System Errors (retryable)
  ENVIRONMENT_CONFIG_ERROR = 'ENVIRONMENT_CONFIG_ERROR',
  UNEXPECTED_ERROR = 'UNEXPECTED_ERROR'
}

interface ClassifiedError {
  code: ErrorCode;
  message: string;
  isRetryable: boolean;
  retryAfterMs?: number;
  context?: Record<string, any>;
}

class SubscriptionError extends Error {
  public readonly code: ErrorCode;
  public readonly isRetryable: boolean;
  public readonly retryAfterMs?: number;
  public readonly context?: Record<string, any>;

  constructor(classifiedError: ClassifiedError) {
    super(classifiedError.message);
    this.name = 'SubscriptionError';
    this.code = classifiedError.code;
    this.isRetryable = classifiedError.isRetryable;
    this.retryAfterMs = classifiedError.retryAfterMs;
    this.context = classifiedError.context;
  }
}

// Error classification helper functions
function classifyDatabaseError(error: any): ClassifiedError {
  const errorMessage = error?.message || error?.toString() || 'Unknown database error';

  // Check for specific database error patterns
  if (errorMessage.includes('timeout') || errorMessage.includes('TIMEOUT')) {
    return {
      code: ErrorCode.DATABASE_TIMEOUT,
      message: 'Database operation timed out. Please try again.',
      isRetryable: true,
      retryAfterMs: 2000,
      context: { originalError: errorMessage }
    };
  }

  if (errorMessage.includes('connection') || errorMessage.includes('CONNECTION')) {
    return {
      code: ErrorCode.DATABASE_CONNECTION_ERROR,
      message: 'Database connection failed. Please try again.',
      isRetryable: true,
      retryAfterMs: 1000,
      context: { originalError: errorMessage }
    };
  }

  if (errorMessage.includes('constraint') || errorMessage.includes('CONSTRAINT')) {
    return {
      code: ErrorCode.DATABASE_CONSTRAINT_ERROR,
      message: 'Database constraint violation. Please contact support.',
      isRetryable: false,
      context: { originalError: errorMessage }
    };
  }

  // Default database error
  return {
    code: ErrorCode.PROFILE_UPDATE_FAILED,
    message: 'Failed to update subscription profile. Please try again.',
    isRetryable: true,
    retryAfterMs: 1500,
    context: { originalError: errorMessage }
  };
}

function classifyGoogleApiError(statusCode: number, errorBody: string): ClassifiedError {
  switch (statusCode) {
    case 401:
    case 403:
      return {
        code: ErrorCode.GOOGLE_AUTH_FAILED,
        message: 'Google Play authentication failed. Please try again.',
        isRetryable: true,
        retryAfterMs: 5000,
        context: { statusCode, errorBody }
      };

    case 408:
    case 504:
      return {
        code: ErrorCode.GOOGLE_API_TIMEOUT,
        message: 'Google Play API timeout. Please try again.',
        isRetryable: true,
        retryAfterMs: 3000,
        context: { statusCode, errorBody }
      };

    case 429:
      return {
        code: ErrorCode.GOOGLE_API_RATE_LIMIT,
        message: 'Google Play API rate limit exceeded. Please wait and try again.',
        isRetryable: true,
        retryAfterMs: 10000,
        context: { statusCode, errorBody }
      };

    case 500:
    case 502:
    case 503:
      return {
        code: ErrorCode.GOOGLE_API_SERVER_ERROR,
        message: 'Google Play API server error. Please try again.',
        isRetryable: true,
        retryAfterMs: 5000,
        context: { statusCode, errorBody }
      };

    default:
      return {
        code: ErrorCode.INVALID_PURCHASE,
        message: `Purchase validation failed: ${errorBody}`,
        isRetryable: false,
        context: { statusCode, errorBody }
      };
  }
}

// Retry mechanism with exponential backoff for database operations
async function retryOperation<T>(
  operation: () => Promise<T>,
  operationName: string,
  maxRetries: number = 3,
  baseDelayMs: number = 1000
): Promise<T> {
  let lastError: SubscriptionError | null = null;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`🔄 Attempting ${operationName} (attempt ${attempt}/${maxRetries})`);
      const result = await operation();

      if (attempt > 1) {
        console.log(`✅ ${operationName} succeeded on attempt ${attempt}`);
      }

      return result;
    } catch (error) {
      console.error(`❌ ${operationName} failed on attempt ${attempt}:`, error);

      // Classify the error
      let classifiedError: ClassifiedError;
      if (error instanceof SubscriptionError) {
        classifiedError = {
          code: error.code,
          message: error.message,
          isRetryable: error.isRetryable,
          retryAfterMs: error.retryAfterMs,
          context: error.context
        };
      } else {
        // Assume it's a database error if not already classified
        classifiedError = classifyDatabaseError(error);
      }

      lastError = new SubscriptionError(classifiedError);

      // If error is not retryable or this is the last attempt, throw immediately
      if (!classifiedError.isRetryable || attempt === maxRetries) {
        console.error(`🚫 ${operationName} failed permanently after ${attempt} attempts`);
        throw lastError;
      }

      // Calculate delay with exponential backoff
      const delay = Math.min(
        classifiedError.retryAfterMs || (baseDelayMs * Math.pow(2, attempt - 1)),
        30000 // Cap at 30 seconds
      );

      console.log(`⏳ Waiting ${delay}ms before retry ${attempt + 1} for ${operationName}`);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }

  // This should never be reached, but just in case
  throw lastError || new SubscriptionError({
    code: ErrorCode.UNEXPECTED_ERROR,
    message: `${operationName} failed after ${maxRetries} attempts`,
    isRetryable: false
  });
}

// Fallback procedures for persistent failures
async function createFailureRecord(
  supabaseClient: any,
  userId: string,
  purchaseContext: { productId: string; purchaseToken: string },
  updatePayload: any,
  error: SubscriptionError
): Promise<void> {
  try {
    console.log('📝 Creating failure record for manual processing...');

    // Create a record in a failed_subscription_updates table for manual processing
    const failureRecord = {
      user_id: userId,
      product_id: purchaseContext.productId,
      purchase_token: purchaseContext.purchaseToken,
      intended_update_payload: updatePayload,
      error_code: error.code,
      error_message: error.message,
      error_context: error.context,
      created_at: new Date().toISOString(),
      status: 'pending_manual_review',
      retry_count: 0
    };

    const { error: insertError } = await supabaseClient
      .from('failed_subscription_updates')
      .insert(failureRecord);

    if (insertError) {
      console.error('❌ Failed to create failure record:', insertError);
      // Don't throw here - this is a fallback, not critical
    } else {
      console.log('✅ Failure record created successfully for manual processing');
    }
  } catch (fallbackError) {
    console.error('❌ Fallback procedure failed:', fallbackError);
    // Log but don't throw - we don't want to fail the entire operation
  }
}

async function notifyAdministrators(
  userId: string,
  purchaseContext: { productId: string; purchaseToken: string },
  error: SubscriptionError
): Promise<void> {
  try {
    console.log('📧 Notifying administrators of critical subscription failure...');

    // In a real implementation, this would send an email, Slack notification, etc.
    // For now, we'll log a structured message that can be picked up by monitoring systems
    console.error('🚨 CRITICAL SUBSCRIPTION FAILURE - ADMIN ATTENTION REQUIRED', {
      severity: 'CRITICAL',
      event: 'subscription_profile_update_failed',
      userId,
      productId: purchaseContext.productId,
      purchaseToken: purchaseContext.purchaseToken.substring(0, 20) + '...',
      errorCode: error.code,
      errorMessage: error.message,
      timestamp: new Date().toISOString(),
      actionRequired: 'Manual profile update needed - user has valid purchase but no subscription benefits'
    });

    // TODO: Integrate with actual notification system (email, Slack, PagerDuty, etc.)
    // Example integrations:
    // - await sendSlackAlert(alertData);
    // - await sendEmailToAdmins(alertData);
    // - await createPagerDutyIncident(alertData);

  } catch (notificationError) {
    console.error('❌ Failed to notify administrators:', notificationError);
    // Don't throw - this is a fallback notification
  }
}

// Enhanced profile update function with retry logic and fallback procedures
async function updateProfileWithRetry(
  supabaseClient: any,
  userId: string,
  updatePayload: any,
  purchaseContext: { productId: string; purchaseToken: string }
): Promise<void> {
  const operation = async () => {
    console.log('💾 Updating user profile with subscription data:', JSON.stringify(updatePayload, null, 2));

    const { error: updateError } = await supabaseClient
      .from('profiles')
      .update(updatePayload)
      .eq('id', userId);

    if (updateError) {
      console.error('❌ Profile update error details:', updateError);

      // Classify and throw the error for retry handling
      const classifiedError = classifyDatabaseError(updateError);
      throw new SubscriptionError({
        ...classifiedError,
        context: {
          ...classifiedError.context,
          userId,
          updatePayload,
          purchaseContext
        }
      });
    }

    console.log('✅ Profile updated successfully');
  };

  try {
    await retryOperation(
      operation,
      'Profile Update',
      5, // More retries for critical profile updates
      1000 // 1 second base delay
    );
  } catch (error) {
    if (error instanceof SubscriptionError) {
      console.error('🚨 Profile update failed permanently after all retries');

      // Execute fallback procedures
      await Promise.all([
        createFailureRecord(supabaseClient, userId, purchaseContext, updatePayload, error),
        notifyAdministrators(userId, purchaseContext, error)
      ]);

      // Re-throw the error with additional context about fallback procedures
      throw new SubscriptionError({
        code: error.code,
        message: `${error.message} Fallback procedures have been initiated for manual resolution.`,
        isRetryable: false,
        context: {
          ...error.context,
          fallbackProceduresExecuted: true,
          manualReviewRequired: true
        }
      });
    }

    throw error;
  }
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

// Function to verify acknowledgment status by re-querying the subscription
async function verifyAcknowledgmentStatus(subscriptionId: string, purchaseToken: string, accessToken: string): Promise<{ acknowledged: boolean; acknowledgementState?: number; error?: string }> {
  try {
    const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${APP_PACKAGE_NAME}/purchases/subscriptions/${subscriptionId}/tokens/${purchaseToken}?access_token=${accessToken}`;

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000); // 15 second timeout

    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      signal: controller.signal
    });

    clearTimeout(timeoutId);

    if (!response.ok) {
      const errorText = await response.text();
      return { acknowledged: false, error: `HTTP ${response.status}: ${errorText}` };
    }

    const purchaseData = await response.json();
    const acknowledgementState = purchaseData.acknowledgementState;

    return {
      acknowledged: acknowledgementState === 1,
      acknowledgementState: acknowledgementState
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return { acknowledged: false, error: errorMessage };
  }
}

// Enhanced function to acknowledge a subscription with retry logic and comprehensive error handling
async function acknowledgeGooglePlaySubscription(subscriptionId: string, purchaseToken: string, accessToken: string, maxRetries: number = 3): Promise<{ success: boolean; error?: string; attempts: number; verified?: boolean }> {
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${APP_PACKAGE_NAME}/purchases/subscriptions/${subscriptionId}/tokens/${purchaseToken}:acknowledge`;

  console.log(`🔄 Starting acknowledgment for subscription ${subscriptionId} (max ${maxRetries} attempts)`);

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      console.log(`📡 Acknowledgment attempt ${attempt}/${maxRetries} for subscription ${subscriptionId}`);

      // Create AbortController for timeout handling
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 30000); // 30 second timeout

      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({}), // Body can be empty for acknowledge
        signal: controller.signal
      });

      clearTimeout(timeoutId);

      if (response.ok) {
        console.log(`✅ Subscription ${subscriptionId} acknowledged successfully on attempt ${attempt}`);

        // Verify the acknowledgment by re-querying the subscription
        console.log(`🔍 Verifying acknowledgment status for ${subscriptionId}...`);
        const verification = await verifyAcknowledgmentStatus(subscriptionId, purchaseToken, accessToken);

        if (verification.acknowledged) {
          console.log(`✅ Acknowledgment verified: ${subscriptionId} is now acknowledged (state: ${verification.acknowledgementState})`);
          return { success: true, attempts: attempt, verified: true };
        } else {
          console.warn(`⚠️ Acknowledgment API returned success but verification failed for ${subscriptionId}. State: ${verification.acknowledgementState}, Error: ${verification.error}`);
          // Still consider it successful since Google API returned 200, but log the discrepancy
          return { success: true, attempts: attempt, verified: false };
        }
      } else {
        const errorText = await response.text();
        const errorMessage = `HTTP ${response.status}: ${errorText}`;
        console.error(`❌ Acknowledgment attempt ${attempt} failed for ${subscriptionId}: ${errorMessage}`);

        // Check if this is a retryable error
        const isRetryable = response.status >= 500 || response.status === 429 || response.status === 408;

        if (!isRetryable || attempt === maxRetries) {
          console.error(`🚫 Non-retryable error or max attempts reached for ${subscriptionId}: ${errorMessage}`);
          return { success: false, error: errorMessage, attempts: attempt };
        }

        // Wait before retrying with exponential backoff
        const delay = Math.min(1000 * Math.pow(2, attempt - 1), 10000); // Cap at 10 seconds
        console.log(`⏳ Waiting ${delay}ms before retry ${attempt + 1} for ${subscriptionId}`);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      console.error(`💥 Exception during acknowledgment attempt ${attempt} for ${subscriptionId}: ${errorMessage}`);

      // Check if this is a timeout or network error (retryable)
      const isRetryable = errorMessage.includes('AbortError') || errorMessage.includes('fetch') || errorMessage.includes('network');

      if (!isRetryable || attempt === maxRetries) {
        console.error(`🚫 Non-retryable exception or max attempts reached for ${subscriptionId}: ${errorMessage}`);
        return { success: false, error: errorMessage, attempts: attempt };
      }

      // Wait before retrying with exponential backoff
      const delay = Math.min(1000 * Math.pow(2, attempt - 1), 10000); // Cap at 10 seconds
      console.log(`⏳ Waiting ${delay}ms before retry ${attempt + 1} for ${subscriptionId} after exception`);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }

  // This should never be reached, but just in case
  return { success: false, error: 'Unexpected error: max retries exceeded', attempts: maxRetries, verified: false };
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

    // --- Enhanced Acknowledgement Logic ---
    if (validationResult.purchaseData && validationResult.purchaseData.acknowledgementState === 0) {
      console.log(`🔔 Subscription ${productId} needs acknowledgement (acknowledgementState: 0). Initiating robust acknowledgment process...`);

      const ackResult = await acknowledgeGooglePlaySubscription(productId, purchaseToken, googleAccessToken, 3);

      if (ackResult.success) {
        const verificationStatus = ackResult.verified ? 'and verified' : 'but verification inconclusive';
        console.log(`✅ Successfully acknowledged subscription ${productId} after ${ackResult.attempts} attempt(s) ${verificationStatus}`);
      } else {
        // This is a critical failure that could lead to refunds
        const errorMsg = `❌ CRITICAL: Failed to acknowledge subscription ${productId} after ${ackResult.attempts} attempts. Error: ${ackResult.error}. This purchase may be automatically refunded by Google Play.`;
        console.error(errorMsg);

        // Still proceed with entitlement update since validation passed, but log the critical issue
        console.warn(`⚠️ Proceeding with entitlement update despite acknowledgment failure. User will receive subscription benefits, but Google Play may issue automatic refund.`);

        // TODO: Consider implementing a background job to retry acknowledgment later
        // TODO: Consider alerting administrators about acknowledgment failures
      }
    } else if (validationResult.purchaseData && validationResult.purchaseData.acknowledgementState === 1) {
      console.log(`✅ Subscription ${productId} is already acknowledged (acknowledgementState: 1)`);
    } else {
      console.log(`ℹ️ Subscription ${productId} acknowledgement state: ${validationResult.purchaseData?.acknowledgementState || 'unknown'}`);
    }
    // --- End Enhanced Acknowledgement ---

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
    
    // Determine tier based on productId (support both legacy and current IDs)
    if (productId === 'monthly_unlimited_generations') {
      tier = 'monthly_unlimited_generations';
    } else if (productId === 'monthly_unlimited') {
      tier = 'monthly_unlimited';
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

    // Use enhanced profile update with retry logic and transaction-like behavior
    try {
      await updateProfileWithRetry(
        supabaseClient,
        user.id,
        updatePayload,
        { productId, purchaseToken }
      );

      // Verify the update was successful by reading back the data
      console.log('🔍 Verifying profile update was successful...');
      const { data: verificationData, error: verificationError } = await supabaseClient
        .from('profiles')
        .select('current_subscription_tier, subscription_active, subscription_expires_at')
        .eq('id', user.id)
        .single();

      if (verificationError || !verificationData) {
        console.error('❌ Profile verification failed:', verificationError);
        throw new Error('Profile update verification failed');
      }

      console.log('✅ Profile verification successful:', {
        tier: verificationData.current_subscription_tier,
        active: verificationData.subscription_active,
        expires: verificationData.subscription_expires_at
      });

      return new Response(JSON.stringify({
        success: true,
        message: 'Subscription activated and profile updated.',
        subscriptionDetails: {
          tier: tier,
          active: isActive,
          expiresAt: expiresAt
        }
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      });
    } catch (profileUpdateError) {
      // Profile update failed after all retries and fallback procedures
      console.error('🚨 CRITICAL: Profile update failed after successful purchase validation and acknowledgment');

      if (profileUpdateError instanceof SubscriptionError) {
        // Return a specific error response that indicates the purchase was successful
        // but profile update failed - this helps the client handle the situation appropriately
        return new Response(JSON.stringify({
          success: false,
          error: profileUpdateError.message,
          errorCode: profileUpdateError.code,
          purchaseStatus: 'acknowledged_but_profile_update_failed',
          context: {
            purchaseValidated: true,
            purchaseAcknowledged: true,
            profileUpdateFailed: true,
            manualReviewRequired: profileUpdateError.context?.manualReviewRequired || false
          },
          userMessage: 'Your purchase was successful and has been acknowledged with Google Play, but there was an issue updating your account. Our support team has been notified and will resolve this shortly. Your subscription benefits will be activated soon.',
          supportInstructions: 'If your subscription is not activated within 24 hours, please contact support with your purchase details.'
        }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 202, // Accepted - indicates partial success
        });
      }

      // Unexpected error type
      throw profileUpdateError;
    }
  } catch (error) {
    console.error('Error in validate-purchase function:', error);

    // Enhanced error response with classification
    if (error instanceof SubscriptionError) {
      return new Response(JSON.stringify({
        success: false,
        error: error.message,
        errorCode: error.code,
        isRetryable: error.isRetryable,
        retryAfterMs: error.retryAfterMs,
        context: error.context
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: error.isRetryable ? 503 : 400, // Service Unavailable for retryable, Bad Request for non-retryable
      });
    }

    // Fallback for unclassified errors
    return new Response(JSON.stringify({
      success: false,
      error: error.message || 'An unexpected error occurred.',
      errorCode: ErrorCode.UNEXPECTED_ERROR,
      isRetryable: false
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    });
  }
}); 