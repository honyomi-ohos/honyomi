// ja/yomonga — Yomonga
// Honest skip: reader is SpeedBinb; page images are scrambled and descrambled by a native
// Bitmap/Canvas interceptor (keiyoushi speedbinb lib). Not portable to the JS plugin runtime.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'SpeedBinb viewer; scrambled images require native bitmap descrambler (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
