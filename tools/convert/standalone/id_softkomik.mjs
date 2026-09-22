// id/softkomik — softkomik.co (Cloudflare WAF + WebView session, honest skip)
//
// Upstream relies on:
//  1. Next.js RSC pages on softkomik.co for library/details — the host is behind a
//     Cloudflare WAF rule that 403-blocks every non-WebView request (all paths, all UAs).
//  2. Chapter-list API (api.softkomik.org) requiring X-Token/X-Sign session headers from
//     softkomik.co/api/session/* endpoints, which are bootstrapped via Set-Cookie handshakes
//     (cookie jar) and fall back to intercepting those headers from a live WebView when the
//     session endpoint is renamed (frequent, per upstream comments).
// The plugin host has no WebView and no cookie jar, so the flow cannot be replicated.

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: false,
    reason: 'Cloudflare WAF blocks the site and chapter API session tokens (X-Token/X-Sign) ' +
      'require a cookie-bootstrapped session endpoint with WebView fallback; no WebView/cookie ' +
      'support in the plugin host',
  };
}

export function generate(manifest) {
  throw new Error('skip: ' + manifest.key);
}
