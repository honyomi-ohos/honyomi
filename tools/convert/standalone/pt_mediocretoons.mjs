// pt/mediocretoons — API (back2.mediocrescan.com) returns 401 for anonymous requests;
// a Bearer token from email/password login is required for all browsing.
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'API requires account login (Bearer token) for all content; not portable',
  };
}

export function generate() {
  throw new Error('not convertible');
}
