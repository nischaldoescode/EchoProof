// translate edge function
// Proxies to Google Translate API (free tier) or LibreTranslate.
// Keeps API keys server-side. Called by echo card for inline translation.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { title, content, target_lang = "en" } = await req.json();
    const apiKey = Deno.env.get("GOOGLE_TRANSLATE_API_KEY");

    if (!apiKey) {
      // Fallback: return original text unchanged.
      return new Response(
        JSON.stringify({ title, content }),
        { headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    const translate = async (text: string): Promise<string> => {
      if (!text) return text;
      const res = await fetch(
        `https://translation.googleapis.com/language/translate/v2?key=${apiKey}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ q: text, target: target_lang, format: "text" }),
        },
      );
      if (!res.ok) return text;
      const data = await res.json() as {
        data: { translations: Array<{ translatedText: string }> };
      };
      return data.data.translations[0]?.translatedText ?? text;
    };

    const [translatedTitle, translatedContent] = await Promise.all([
      translate(title ?? ""),
      translate(content ?? ""),
    ]);

    return new Response(
      JSON.stringify({ title: translatedTitle, content: translatedContent }),
      { headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("translate error:", e);
    return new Response(
      JSON.stringify({ error: "translation failed" }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }
});