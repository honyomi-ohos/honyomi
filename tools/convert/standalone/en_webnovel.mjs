// en/webnovel — SKIP: every API request goes through csrfTokenInterceptor, which
// throws unless the _csrfToken cookie was set by WebView JavaScript. The plugin
// host has no WebView and no cookie access, so all content is unobtainable.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'all API requests require _csrfToken cookie that can only be obtained via WebView javascript; no cookie/WebView support in plugin host',
  };
}

export function generate() {
  throw new Error('skipped source');
}
