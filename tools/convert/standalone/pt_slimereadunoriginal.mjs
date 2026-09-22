// pt/slimereadunoriginal — site is dead: slimeread.app has no DNS resolution
export const runtime = 'wp';

export function extract(ctx) {
  return {
    ok: false,
    reason: 'site dead — slimeread.app no longer resolves in DNS',
  };
}

export function generate() {
  throw new Error('not convertible');
}
