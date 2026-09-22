// en/mangamirai — SKIP: page images are AES-CBC encrypted (key = SHA-256("manga{contentsId}mirai"),
// IV = first 16 bytes of the image body) and then 96x96 tile-unscrambled client-side, with the
// result re-encoded to JPEG — a native bitmap pipeline (see ImageInterceptor.kt). The plugin host
// is text-only (no binary bodies, no canvas/bitmap ops), so page images cannot be rendered.
// Additionally, many chapters are purchase-gated (HTTP 500 "Log in via WebView and purchase").
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'AES-CBC encrypted + tile-scrambled page images require native bitmap descramble interceptor (not portable); many chapters purchase-gated',
  };
}

export function generate() {
  throw new Error('skipped source');
}
