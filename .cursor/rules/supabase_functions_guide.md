# Supabase Functions Guide

The project uses Supabase Edge Functions for backend logic. Functions are organized as follows:

- [supabase/functions/](mdc:supabase/functions): Top-level serverless functions.
  - [report-support-issue/](mdc:supabase/functions/report-support-issue): Handles support issue reporting.
    - [index.ts](mdc:supabase/functions/report-support-issue/index.ts): Main entry point.
    - [cors.ts](mdc:supabase/functions/report-support-issue/cors.ts): CORS middleware.
  - [_shared/](mdc:supabase/functions/_shared): Shared code for functions.
    - [cors.ts](mdc:supabase/functions/_shared/cors.ts): Shared CORS logic.
  - [delete-account/](mdc:supabase/functions/delete-account): Handles account deletion.
    - [index.ts](mdc:supabase/functions/delete-account/index.ts): Main entry point.
  - [get-gallery-feed/](mdc:supabase/functions/get-gallery-feed): Handles gallery feed retrieval.
    - [index.ts](mdc:supabase/functions/get-gallery-feed/index.ts): Main entry point.
  - [generate-image-proxy/](mdc:supabase/functions/generate-image-proxy): DALL-E 3 image generation proxy.
    - [index.ts](mdc:supabase/functions/generate-image-proxy/index.ts): Main entry point.
  - [enhance-image-proxy/](mdc:supabase/functions/enhance-image-proxy): DALL-E 2 image-to-image enhancement proxy.
    - [index.ts](mdc:supabase/functions/enhance-image-proxy/index.ts): Main entry point for image enhancement using DALL-E 2.
  - [get-generation-status/](mdc:supabase/functions/get-generation-status): Status checking for image generation.
    - [index.ts](mdc:supabase/functions/get-generation-status/index.ts): Main entry point.
  - [get-random-prompt/](mdc:supabase/functions/get-random-prompt): Random prompt generation.
    - [index.ts](mdc:supabase/functions/get-random-prompt/index.ts): Main entry point.
  - [improve-prompt-proxy/](mdc:supabase/functions/improve-prompt-proxy): Prompt improvement using AI.
    - [index.ts](mdc:supabase/functions/improve-prompt-proxy/index.ts): Main entry point.
  - [validate-purchase-and-update-profile/](mdc:supabase/functions/validate-purchase-and-update-profile): In-app purchase validation.
    - [index.ts](mdc:supabase/functions/validate-purchase-and-update-profile/index.ts): Main entry point.

Each function directory contains an [index.ts](mdc:index.ts) as the main handler.