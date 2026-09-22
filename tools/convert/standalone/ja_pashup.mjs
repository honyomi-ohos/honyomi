// ja/pashup — PashUp (Publus platform)
// Honest skip: pages delivered via the Publus viewer with block-scrambled images that need
// the native PublusInterceptor (Bitmap/Canvas). Not portable to the JS plugin runtime.
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
