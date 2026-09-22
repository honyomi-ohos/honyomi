// en/mangago — SKIP: page images are AES-encrypted (key from SoJsonV4-obfuscated chapter.js
// evaluated in QuickJS) and descrambled via native canvas bitmap operations.
// The plugin host cannot eval remote JS nor descramble images.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'image list requires QuickJS deobfuscation of chapter.js + AES decrypt, and cspiclink images need native canvas descrambling; unsupported in plugin host',
  };
}

export function generate() {
  throw new Error('skipped source');
}
