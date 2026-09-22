// ClipStudioReader theme engine (ja: comicfesta, firecross) — NOT SUPPORTED by plugin host
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'clipstudioreader requires byte-level response interceptors (XOR-key deobfuscation of first 1024 bytes for EPUB images, and canvas tile-unscrambling for scrambled page images) plus a two-step page fetch (Page.url XML -> imageUrlParse); the plugin host loads images directly by URL and cannot post-process image bytes'
  };
}

export function generate(manifest, config) {
  throw new Error('clipstudioreader is not supported by the plugin host');
}
