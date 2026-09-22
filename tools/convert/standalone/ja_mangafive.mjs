// ja/mangafive — MangaFive (Publus platform)
// Honest skip: pages delivered via Publus license API and images are block-scrambled;
// unscrambling requires the native PublusInterceptor (Bitmap/Canvas) which the JS plugin
// runtime cannot perform.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'Publus viewer: scrambled images require native bitmap unscramble interceptor (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
