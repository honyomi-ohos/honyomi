// pt/shiraiscans — site is dead: shiraixis.space 302-redirects to google.com
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'site dead — domain redirects to google.com',
  };
}

export function generate() {
  throw new Error('not convertible');
}
