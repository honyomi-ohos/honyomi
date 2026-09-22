// ja/mangaparkpublisher — MangaPark (publisher site)
// Honest skip: page images are XOR-encrypted with a per-image base64 key; decryption
// requires a byte-level OkHttp interceptor the JS plugin runtime cannot provide.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'XOR-encrypted page images; requires native byte interceptor (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
