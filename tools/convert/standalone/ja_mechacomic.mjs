// ja/mechacomic — MechaComic
// Honest skip: page images are AES-CBC encrypted at byte level (native Cipher interceptor);
// not portable to the JS plugin runtime.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'AES-CBC encrypted page images; requires native byte interceptor (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
