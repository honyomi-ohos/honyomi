// en/mangalix — SKIP: chapter list is served as a gzip archive ({base}/chapters.json.gz)
// fetched with Accept: application/gzip. The plugin host's http.get decodes every body as
// UTF-8 text, so the gzip bytes are destroyed before any decompression could run, and the
// runtime provides no binary/inflate API. (The catalog itself — a JS literal array embedded
// in the bundled assets/main-*.js — would be parseable, but without the chapter archive the
// source cannot list chapters or pages.)
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'chapter data only available as gzip file (chapters.json.gz); host runtime is text-only with no inflate support',
  };
}

export function generate() {
  throw new Error('skipped source');
}
