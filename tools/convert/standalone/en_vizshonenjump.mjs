// en/vizshonenjump — SKIP: image server returns scrambled JPEGs that the original
// extension unscrambles in a native Android interceptor (Bitmap/Canvas XOR-style
// reconstruction keyed by an EXIF tag). This is impossible in the JS sandbox.
// Most chapters additionally require a Viz Media subscription (login).
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'images are scrambled server-side and unscrambled with native Android Bitmap/Canvas + EXIF key; most chapters also require Viz subscription login',
  };
}

export function generate() {
  throw new Error('skipped source');
}
