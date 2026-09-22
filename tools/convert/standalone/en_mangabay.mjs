// en/mangabay — SKIP: every request is redirected to the DLE "_c" guard challenge
// (manga-bay.biz/_c?t=...), which upstream solves with a WebView cookie (__guard_trust).
// The plugin host has no WebView, so all content is unobtainable.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'DLE guard challenge on every request (WebView-solved upstream via __guard_trust cookie); no WebView in plugin host',
  };
}

export function generate() {
  throw new Error('skipped source');
}
