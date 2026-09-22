// ja/zebrack — Zebrack
// Honest skip: page images are XOR-encrypted with a per-image key from the URL fragment,
// decrypted by a native OkHttp interceptor (byte-level response transform). The JS plugin
// runtime has no response-interception capability, so this cannot be replicated.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'XOR-encrypted images require native response interceptor (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
