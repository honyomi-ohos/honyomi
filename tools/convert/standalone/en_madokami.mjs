// en/madokami — SKIP: requires user HTTP Basic auth credentials (username/password preferences)
// for every request; also uses zip range requests for .zip/.cbz chapters.
// The plugin host has no credential storage, so all content is unobtainable without login.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'requires login (HTTP Basic auth credentials in prefs) for all requests; zip-range chapter reading unsupported',
  };
}

export function generate() {
  throw new Error('skipped source');
}
