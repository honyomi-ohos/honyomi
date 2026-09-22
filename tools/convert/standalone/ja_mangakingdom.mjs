// ja/mangakingdom — Manga Kingdom (k-manga.jp)
// Honest skip: viewer content arrives as base64 scenes that must be block-unscrambled with
// a native Bitmap/Canvas interceptor (LCG block shuffle); not portable to the JS plugin runtime.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'viewer images base64+scrambled; requires native bitmap unscramble interceptor (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
