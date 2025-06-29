// supabase/functions/get-random-prompt/index.ts

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";

const prompts = [
  "A steampunk owl delivering a glowing letter at midnight.",
  "An ancient library hidden inside a giant, moss-covered tree.",
  "A cyberpunk city street during a neon-drenched rainstorm, reflections on wet pavement.",
  "A majestic griffin soaring above snow-capped mountains at sunset.",
  "A whimsical tea party in a mushroom forest with talking animals.",
  "A lone astronaut discovering a mysterious alien artifact on Mars.",
  "A secret garden blooming under a sky full of binary code.",
  "A retro-futuristic diner on a space station overlooking Earth.",
  "A fantasy warrior with glowing runes on their armor, ready for battle.",
  "An underwater city made of coral and bioluminescent plants.",
  "A child riding a giant, friendly robot through a field of wildflowers.",
  "A surreal landscape where clocks melt and the sky is made of flowing fabric.",
  "A hidden waterfall cascading into a crystal-clear pool in a dense jungle.",
  "A portrait of a wise old wizard with a long white beard and sparkling eyes.",
  "A futuristic vehicle speeding through a desert towards a neon oasis.",
  "A dragon peacefully sleeping on a hoard of books instead of gold.",
  "A ghostly pirate ship sailing through a foggy, moonlit sea.",
  "An enchanted forest path with glowing flowers and ethereal creatures.",
  "A detailed close-up of a mechanical insect with intricate gears.",
  "A serene zen garden on a floating island among the clouds."
];

serve(async (req) => {
  // Handle OPTIONS preflight request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const randomIndex = Math.floor(Math.random() * prompts.length);
    const randomPrompt = prompts[randomIndex];

    return new Response(
      JSON.stringify({ prompt: randomPrompt }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  } catch (error) {
    console.error("Error in get-random-prompt:", error.message);
    return new Response(
      JSON.stringify({ error: "Failed to retrieve a random prompt." }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});
