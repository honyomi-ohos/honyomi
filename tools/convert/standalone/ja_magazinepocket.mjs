// ja/magazinepocket — MagazinePocket (official app API)
// Honest skip: viewer page images are 4x4-block scrambled; unscrambling requires a native
// Bitmap/Canvas interceptor (xorshift32 seed + block shuffle) that the JS plugin runtime
// cannot perform. Metadata/chapters are obtainable but every page image would be scrambled.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'pages served scrambled; requires native bitmap unscramble interceptor (not portable to JS plugin)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
