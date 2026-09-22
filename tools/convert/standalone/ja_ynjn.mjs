// ja/ynjn — Comic Walker (ynjn.jp)
// Honest skip: viewer images are 4x4-grid transposition-scrambled and unscrambled by a
// native Bitmap/Canvas interceptor (#scramble). Not portable to the JS plugin runtime.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'Grid-scrambled images require native bitmap unscramble interceptor (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
