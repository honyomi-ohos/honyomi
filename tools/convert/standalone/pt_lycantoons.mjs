// pt/lycantoons — every request is proxied through a WebView because plain HTTP
// clients get 403 (Cloudflare TLS fingerprint checks). Not portable to plugin runtime.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'all requests require WebView proxy (Cloudflare TLS fingerprint); not portable',
  };
}

export function generate() {
  throw new Error('not convertible');
}
