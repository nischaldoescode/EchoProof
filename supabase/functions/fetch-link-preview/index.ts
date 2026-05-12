// fetch-link-preview edge function
// Fetches Open Graph metadata for a given URL.
// Runs server-side to avoid CORS issues and to sanitize the URL first.
// Returns: title, description, image, site_name, favicon.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Allowlist check — refuse to fetch internal/private IP ranges.
function isSafeUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    const host = parsed.hostname.toLowerCase();

    // Block private ranges and localhost.
    if (
      host === "localhost" ||
      host === "127.0.0.1" ||
      host.startsWith("192.168.") ||
      host.startsWith("10.") ||
      host.startsWith("172.16.") ||
      host.endsWith(".local") ||
      host === "0.0.0.0"
    ) {
      return false;
    }

    // Only allow http and https.
    if (!["http:", "https:"].includes(parsed.protocol)) {
      return false;
    }

    return true;
  } catch {
    return false;
  }
}

function extractMeta(html: string, baseUrl: string): Record<string, string> {
  const get = (pattern: RegExp): string => {
    const m = html.match(pattern);
    return m ? m[1].replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').trim() : '';
  };

  const title =
    get(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']/i) ||
    get(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']/i) ||
    get(/<title[^>]*>([^<]+)<\/title>/i);

  const description =
    get(/<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)["']/i) ||
    get(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:description["']/i) ||
    get(/<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)["']/i);

  const rawImage =
    get(/<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i) ||
    get(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i);

  const siteName =
    get(/<meta[^>]+property=["']og:site_name["'][^>]+content=["']([^"']+)["']/i) ||
    get(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:site_name["']/i);

  // Favicon: prefer link[rel=icon] or default /favicon.ico
  const faviconRel =
    get(/<link[^>]+rel=["'](?:shortcut )?icon["'][^>]+href=["']([^"']+)["']/i) ||
    get(/<link[^>]+href=["']([^"']+)["'][^>]+rel=["'](?:shortcut )?icon["']/i);

  const parsed = new URL(baseUrl);
  const image = rawImage
    ? (rawImage.startsWith('http') ? rawImage : new URL(rawImage, parsed.origin).toString())
    : '';
  const favicon = faviconRel
    ? (faviconRel.startsWith('http') ? faviconRel : `${parsed.origin}${faviconRel.startsWith('/') ? '' : '/'}${faviconRel}`)
    : `${parsed.origin}/favicon.ico`;

  return { title, description, image, site_name: siteName, favicon };
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const { url } = await req.json() as { url: string };

    if (!url || !isSafeUrl(url)) {
      return new Response(
        JSON.stringify({ error: "invalid or unsafe url" }),
        { status: 400, headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    // Fetch with a 5-second timeout.
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);

    try {
      const res = await fetch(url, {
        signal: controller.signal,
        headers: {
          "User-Agent": "EchoproofBot/1.0 (+https://echoproof.online)",
          "Accept": "text/html",
        },
        redirect: "follow",
      });

      clearTimeout(timeout);

      if (!res.ok) {
        return new Response(
          JSON.stringify({ error: "fetch failed" }),
          { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
        );
      }

      // Only process text/html responses.
      const contentType = res.headers.get("content-type") ?? "";
      if (!contentType.includes("text/html")) {
        return new Response(
          JSON.stringify({ error: "not html" }),
          { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
        );
      }

      // Read first 100KB only — enough for OG tags in the head.
      const reader = res.body?.getReader();
      let html = "";
      if (reader) {
        let bytesRead = 0;
        while (bytesRead < 100_000) {
          const { done, value } = await reader.read();
          if (done) break;
          html += new TextDecoder().decode(value);
          bytesRead += value.byteLength;
        }
        reader.cancel();
      }

      const meta = extractMeta(html, url);

      return new Response(
        JSON.stringify(meta),
        { headers: { ...CORS, "Content-Type": "application/json" } },
      );
    } catch (e) {
      clearTimeout(timeout);
      if ((e as Error).name === "AbortError") {
        return new Response(
          JSON.stringify({ error: "timeout" }),
          { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
        );
      }
      throw e;
    }
  } catch (e) {
    console.error("fetch-link-preview error:", e);
    return new Response(
      JSON.stringify({ error: "internal error" }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }
});
