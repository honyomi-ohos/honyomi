// ja/mokuro — Mokuro reader
// Honest skip: pages are stored inside CBZ zip archives fetched through a native
// zip interceptor (HTTP byte-range reads). Not portable to the JS plugin runtime.
export const runtime = 'wp';

export function extract() {
  return {
    ok: false,
    reason: 'pages inside CBZ archives; requires native zip interceptor (not portable)',
  };
}

export function generate() {
  throw new Error('not convertible');
}
