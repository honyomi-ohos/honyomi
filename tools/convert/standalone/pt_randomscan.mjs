// pt/randomscan (LuraToon) — chapter images are AES-CTR encrypted zip streams that the
// app-side ZipInterceptor decrypts with a key derived from query params; the plugin
// runtime cannot intercept/decrypt image responses, so pages are unrenderable.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'images are AES-CTR encrypted zip streams decrypted by an app-side interceptor; not portable',
  };
}

export function generate() {
  throw new Error('not convertible');
}
