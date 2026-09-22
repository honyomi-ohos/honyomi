// ja/mangasaison — MangaSaison (cominavi)
// Honest skip: pages are served inside a token-protected .uze ZIP archive; reading requires
// native zip-interceptors (byte-range requests + entry decryption). Not portable.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'pages inside token-protected zip archive; requires native zip/byte interceptors (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
