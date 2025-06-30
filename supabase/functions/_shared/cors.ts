// supabase/functions/_shared/cors.ts
export const corsHeaders = {
  "Access-Control-Allow-Origin": "YOUR_APP_DOMAIN_HERE", // IMPORTANT: Replace this with your actual frontend application's domain in production. For multiple domains, you might need more complex logic or to list them if your server/gateway supports it. For development, you can use '*' or 'http://localhost:YOUR_PORT'.
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS, PUT, DELETE", // Added GET, PUT, DELETE to be more general, though many functions might only use POST/OPTIONS.
};