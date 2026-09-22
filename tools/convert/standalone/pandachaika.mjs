// all/pandachaika — SKIP: pages are read out of a remote ZIP via HTTP Range requests
// (keiyoushi zipDirectory interceptor + 127.0.0.1 image shim). The plugin host HTTP DSL
// is text-only, so zip entry bytes cannot be decoded; the site exposes no per-image URLs.
export function extract(ctx) {
  return {
    ok: false,
    reason: 'page list requires binary ZIP range-request fetching (zipDirectory interceptor); text-only HTTP DSL cannot decode zip entries',
  };
}

export function generate() {
  return '';
}
