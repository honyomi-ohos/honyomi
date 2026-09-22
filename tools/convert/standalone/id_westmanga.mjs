// id/westmanga — westmanga.my (API rotated behind obfuscated SPA client, honest skip)
//
// Upstream targets https://data.mantweh.online with HMAC-SHA256-signed requests
// (x-wm-request-time / x-wm-accses-key / x-wm-request-signature, keys
// WM_WEB_FRONT_END / xxxoidj). The site has since been rebuilt as a React Router SPA:
//  - every old API path (/api/contents, /api/comic/<slug>, /api/v/<slug>) now returns 404
//  - the new client's build config has VITE_API_ACCESS_KEY/SECRET_KEY = undefined; the
//    signing scheme and paths live only inside heavily obfuscated bundle code and are
//    resolved at runtime
// Recovering the new scheme requires executing the site's obfuscated JavaScript
// (WebView), which the plugin host does not provide.

export const runtime = 'wp';

export function extract(ctx) {
  if (ctx.gradle.sources.length > 1) return { ok: false, reason: 'multi-source ext' };
  return {
    ok: false,
    reason: 'site rebuilt as SPA; API endpoints and HMAC signing scheme are hidden in obfuscated ' +
      'client JavaScript resolved at runtime — requires WebView execution, unavailable in plugin host',
  };
}

export function generate(manifest) {
  throw new Error('skip: ' + manifest.key);
}
