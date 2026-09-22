// ja/readerstore — Reader Store
// Honest skip: viewer images are encrypted and tile-scrambled, decrypted/unscrambled by a
// native interceptor (custom cipher + Bitmap/Canvas). Not portable to the JS plugin runtime.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'Encrypted/scrambled viewer images require native cipher + bitmap unscramble interceptor (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
