// id/mangakuri — mangakuri.online: chapter pages require a Bearer token obtained
// by logging in via WebView (localStorage). No pages are available anonymously.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'chapter images require WebView login token (Bearer from localStorage); all content login-gated',
  };
}
