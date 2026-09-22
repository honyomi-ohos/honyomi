// PAM theme engine (Laravel Inertia reader: theblank / epsilonscan / softepsilonscan)
//
// Honest skip: PAM's reading flow cannot be ported to the plugin sandbox.
// - Reader v1 pages are encrypted with libsodium secretstream (XChaCha20-Poly1305),
//   keyed by an X25519 ECDH shared secret; neither X25519 nor secretstream exists in
//   WebCrypto (crypto.subtle only offers ECDH over NIST curves and AES/GCM).
// - Reader v2 pages use RFC 8188 ECE (aes128gcm), keyed via an attestation exchange
//   (/api/v1/t) that requires a per-site `readerSecret` recovered from the site's WASM
//   signer (see upstream IMPLEMENT.md) — not available in source form.
// - Both flows additionally need live image-response interception (X-Page-Name /
//   X-Key-Hint headers, streaming decrypt), which the host $ DSL cannot express
//   ($.http.get returns only the response body text).
export const runtime = 'wp';

export function extract(_ctx) {
  return {
    ok: false,
    reason: 'PAM pages are encrypted end-to-end (X25519 ECDH + libsodium secretstream / RFC 8188 ECE with per-site WASM-derived readerSecret); not portable to the plugin sandbox',
  };
}

export function generate(_manifest, _config) {
  return '';
}
