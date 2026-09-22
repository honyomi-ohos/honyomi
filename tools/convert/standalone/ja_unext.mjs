// ja/unext — U-NEXT
// Honest skip: pages are AES/CBC-encrypted entries inside remote ZIP archives (HTTP range
// requests decrypted by a native interceptor); also uses a WebView to obtain viewer data.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'AES-CBC encrypted ZIP-entry images require native interceptor + WebView viewer data (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
