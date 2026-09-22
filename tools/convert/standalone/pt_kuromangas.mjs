// pt/kuromangas — requires account login (kuro_session cookie) for ALL API requests,
// plus Rabbit-cipher response decryption with a key scraped from the site's JS bundle.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'login (email/password) required for all content + Rabbit-cipher encrypted responses; not portable',
  };
}

export function generate() {
  throw new Error('not convertible');
}
