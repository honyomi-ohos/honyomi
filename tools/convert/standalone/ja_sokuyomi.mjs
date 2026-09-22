// ja/sokuyomi — Sokuyomi
// Honest skip: viewer images are 4x4-grid transposition-scrambled and unscrambled by a
// native Bitmap/Canvas interceptor (#scramble); viewer also requires account login.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'Grid-scrambled viewer images require native bitmap unscramble interceptor; login-gated viewer (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
