// ja/piccoma — Piccoma
// Honest skip: page images are tile-scrambled (50px tiles, SeedRandom shuffle) and
// unscrambled by a native Bitmap/Canvas interceptor. Not portable to the JS plugin runtime.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'Tile-scrambled images require native bitmap unscramble interceptor (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
